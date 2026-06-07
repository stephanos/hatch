use crate::process::ProcessRunner;
use crate::{Error, Result};
use camino::Utf8Path;

#[derive(Debug, Default, Clone)]
pub(crate) struct GitCli {
    runner: ProcessRunner,
}

impl GitCli {
    pub(crate) fn origin_url(&self, repo_path: &Utf8Path) -> Result<String> {
        self.runner.run(
            "git",
            &[
                "-C".to_string(),
                repo_path.to_string(),
                "remote".to_string(),
                "get-url".to_string(),
                "origin".to_string(),
            ],
            None,
            None,
        )
    }

    pub(crate) fn status_porcelain(&self, repo_path: &Utf8Path) -> Result<String> {
        self.runner.run(
            "git",
            &[
                "-C".to_string(),
                repo_path.to_string(),
                "status".to_string(),
                "--porcelain".to_string(),
                "--untracked-files=normal".to_string(),
            ],
            None,
            None,
        )
    }

    pub(crate) fn current_branch(&self, repo_path: &Utf8Path) -> Result<String> {
        self.runner.run(
            "git",
            &[
                "-C".to_string(),
                repo_path.to_string(),
                "branch".to_string(),
                "--show-current".to_string(),
            ],
            None,
            None,
        )
    }

    pub(crate) fn remote_branch_exists(&self, repo_path: &Utf8Path, branch: &str) -> bool {
        self.runner
            .run(
                "git",
                &[
                    "-C".to_string(),
                    repo_path.to_string(),
                    "show-ref".to_string(),
                    "--verify".to_string(),
                    "--quiet".to_string(),
                    format!("refs/remotes/origin/{branch}"),
                ],
                None,
                None,
            )
            .is_ok()
    }

    pub(crate) fn delete_remote_branch(&self, repo_path: &Utf8Path, branch: &str) -> Result<()> {
        self.runner
            .run(
                "git",
                &[
                    "-C".to_string(),
                    repo_path.to_string(),
                    "push".to_string(),
                    "--delete".to_string(),
                    "origin".to_string(),
                    branch.to_string(),
                ],
                None,
                None,
            )
            .map(|_| ())
            .map_err(|source| {
                Error::Message(format!(
                    "failed to delete remote branch for {repo_path}: {source}"
                ))
            })
    }
}
