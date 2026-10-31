use super::cleanup_plan::CleanupScanMode;
use super::hook_adapter::{RepoDeleteHook, WorkspaceHookAdapter};
use super::location;
use super::shared::WorkspaceServiceCore;
use crate::{AppPaths, Error, Result, TaskSummary};

const GH_RATE_LIMITED: &str = "GH_RATE_LIMITED";

#[derive(Debug, Clone)]
pub(super) struct RepoCleanupAssessor {
    core: WorkspaceServiceCore,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct RepoCleanupReason {
    pub(super) reasons: Vec<String>,
    pub(super) dry_run_hook: Option<camino::Utf8PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct RepoCleanupCheck {
    pub(super) reasons: Vec<String>,
    pub(super) status: Option<CleanupRepoStatus>,
    pub(super) dry_run_hook: Option<camino::Utf8PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum CleanupRepoStatus {
    Dirty,
    Merged,
    Closed,
    Open,
    GithubRateLimited,
    NoPr,
    NoBranch,
    NoRepos,
    Other(String),
}

impl CleanupRepoStatus {
    pub(super) fn label(&self) -> String {
        match self {
            Self::Dirty => "DIRTY".to_string(),
            Self::Merged => "MERGED".to_string(),
            Self::Closed => "CLOSED".to_string(),
            Self::Open => "OPEN".to_string(),
            Self::GithubRateLimited => GH_RATE_LIMITED.to_string(),
            Self::NoPr => "NO_PR".to_string(),
            Self::NoBranch => "NO_BRANCH".to_string(),
            Self::NoRepos => "No repos".to_string(),
            Self::Other(value) => value.clone(),
        }
    }
}

impl RepoCleanupAssessor {
    pub(super) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(super) fn rate_limited_label() -> &'static str {
        GH_RATE_LIMITED
    }

    pub(super) fn cleanup_remote_branch_for_repo(
        &self,
        repo_path: &camino::Utf8Path,
    ) -> Result<()> {
        let branch = self.core.git.current_branch(repo_path).unwrap_or_default();
        let branch = branch.trim();
        if branch.is_empty() {
            return Ok(());
        }

        if !self.core.git.remote_branch_exists(repo_path, branch) {
            return Ok(());
        }

        self.core.git.delete_remote_branch(repo_path, branch)
    }

    pub(super) fn assess_repo_cleanup(
        &self,
        paths: &AppPaths,
        task: &TaskSummary,
        repo_path: &camino::Utf8Path,
        mode: CleanupScanMode,
    ) -> Result<RepoCleanupCheck> {
        let reason = self.cleanup_reason_for_repo(paths, task, repo_path)?;
        let status = if mode.includes_status() {
            Some(self.cleanup_repo_status(repo_path)?)
        } else {
            None
        };
        Ok(RepoCleanupCheck {
            reasons: reason.reasons,
            status,
            dry_run_hook: reason.dry_run_hook,
        })
    }

    pub(super) fn cleanup_reason_for_repo(
        &self,
        paths: &AppPaths,
        task: &TaskSummary,
        repo_path: &camino::Utf8Path,
    ) -> Result<RepoCleanupReason> {
        let project_path = location::project_path_for_task_path(&task.path)?;
        let repo_path = repo_path.to_path_buf();
        let outcome = WorkspaceHookAdapter::new(self.core.clone()).capture_repo_delete_dry_run(
            RepoDeleteHook {
                paths,
                project_path: &project_path,
                task_path: &task.path,
                repo_path: &repo_path,
            },
        );
        let dry_run_hook = outcome
            .as_ref()
            .and_then(|outcome| outcome.hook_file().cloned());
        let mut reasons = outcome
            .and_then(|outcome| outcome.output().map(ToString::to_string))
            .unwrap_or_default()
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(ToString::to_string)
            .collect::<Vec<_>>();
        if reasons.is_empty()
            && let Some(reason) = self.cleanup_reason_from_git(&repo_path)?
        {
            reasons.push(reason);
        }
        Ok(RepoCleanupReason {
            reasons,
            dry_run_hook,
        })
    }

    fn cleanup_reason_from_git(&self, repo_path: &camino::Utf8Path) -> Result<Option<String>> {
        let branch = match self.core.git.current_branch(repo_path) {
            Ok(branch) => branch,
            Err(_) => return Ok(None),
        };
        let branch = branch.trim().to_string();
        if branch.is_empty() {
            return Ok(None);
        }
        let output = match self
            .core
            .github
            .pull_request_cleanup_reason(repo_path, &branch)
        {
            Ok(output) => output,
            Err(_) => return Ok(None),
        };
        match output.trim() {
            "MERGED" | "CLOSED" => Ok(Some(output.trim().to_string())),
            _ => Ok(None),
        }
    }

    pub(super) fn cleanup_repo_status(
        &self,
        repo_path: &camino::Utf8Path,
    ) -> Result<CleanupRepoStatus> {
        let status = self
            .core
            .git
            .status_porcelain(repo_path)
            .unwrap_or_default();
        if !status.trim().is_empty() {
            return Ok(CleanupRepoStatus::Dirty);
        }

        let branch = self.core.git.current_branch(repo_path).unwrap_or_default();
        let branch = branch.trim().to_string();
        if branch.is_empty() {
            return Ok(CleanupRepoStatus::NoBranch);
        }

        let state = match self.core.github.pull_request_state(repo_path, &branch) {
            Ok(state) => state,
            Err(error) if is_github_rate_limited_error(&error) => {
                return Ok(CleanupRepoStatus::GithubRateLimited);
            }
            Err(_) => String::new(),
        };
        if state.trim().is_empty() {
            Ok(CleanupRepoStatus::NoPr)
        } else {
            Ok(match state.trim() {
                "MERGED" => CleanupRepoStatus::Merged,
                "CLOSED" => CleanupRepoStatus::Closed,
                "OPEN" => CleanupRepoStatus::Open,
                other => CleanupRepoStatus::Other(other.to_string()),
            })
        }
    }
}

pub(super) fn is_github_rate_limited_error(error: &Error) -> bool {
    let message = error.to_string().to_ascii_lowercase();
    message.contains("429")
        || message.contains("too many requests")
        || message.contains("rate limit")
        || message.contains("api rate limit exceeded")
        || message.contains("secondary rate limit")
        || message.contains("abuse detection")
}

#[cfg(test)]
mod tests {
    use super::*;
    use camino::Utf8PathBuf;
    use std::process::Command;

    fn git(repo: &camino::Utf8Path, args: &[&str]) -> String {
        let output = Command::new("git")
            .arg("-C")
            .arg(repo)
            .args(args)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap()
    }

    fn fixture() -> (
        tempfile::TempDir,
        Utf8PathBuf,
        Utf8PathBuf,
        RepoCleanupAssessor,
    ) {
        let temp = tempfile::tempdir().unwrap();
        let root = Utf8PathBuf::from_path_buf(temp.path().to_path_buf()).unwrap();
        let repo = root.join("repo");
        let remote = root.join("remote.git");
        git(&root, &["init", "--bare", remote.as_str()]);
        git(&root, &["init", "--initial-branch", "done", repo.as_str()]);
        git(
            &repo,
            &[
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "commit",
                "--allow-empty",
                "-m",
                "init",
            ],
        );
        git(&repo, &["remote", "add", "origin", remote.as_str()]);
        git(&repo, &["push", "-u", "origin", "done"]);
        let store = crate::HatchStore::new(crate::HatchEnvironment::new(Some(root)));
        let assessor = RepoCleanupAssessor::new(WorkspaceServiceCore::new(store));
        (temp, repo, remote, assessor)
    }

    #[test]
    fn cleanup_skips_remote_branch_deleted_since_last_fetch() {
        let (_temp, repo, remote, assessor) = fixture();
        git(&remote, &["update-ref", "-d", "refs/heads/done"]);
        git(&repo, &["show-ref", "--verify", "refs/remotes/origin/done"]);

        assessor.cleanup_remote_branch_for_repo(&repo).unwrap();
    }

    #[test]
    fn cleanup_deletes_existing_remote_branch() {
        let (_temp, repo, remote, assessor) = fixture();

        assessor.cleanup_remote_branch_for_repo(&repo).unwrap();

        assert!(git(&remote, &["for-each-ref", "refs/heads/done"]).is_empty());
    }

    #[test]
    fn cleanup_reports_unreachable_remote() {
        let (_temp, repo, remote, assessor) = fixture();
        fs_err::remove_dir_all(remote).unwrap();

        assert!(assessor.cleanup_remote_branch_for_repo(&repo).is_err());
        assert!(repo.exists());
    }

    #[test]
    fn default_delete_hook_handles_stale_remote_tracking_ref() {
        let (_temp, repo, remote, _assessor) = fixture();
        git(&remote, &["update-ref", "-d", "refs/heads/done"]);
        let output = Command::new("sh")
            .arg(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/templates/hooks/repo_delete.sh"
            ))
            .args(["--repo-path", repo.as_str()])
            .env(
                "HATCH_HOOK_LIB_DIR",
                concat!(env!("CARGO_MANIFEST_DIR"), "/templates/lib"),
            )
            .output()
            .unwrap();

        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            !repo.exists(),
            "hook left the checkout behind: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
}
