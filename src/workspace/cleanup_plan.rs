use super::cleanup_assessment::{CleanupRepoStatus, RepoCleanupAssessor, RepoCleanupCheck};
use crate::CleanupCandidate;
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CleanupCandidateView {
    pub candidate: CleanupCandidate,
    pub repos: Vec<String>,
    pub status: String,
    pub default_selected: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct TaskCleanupAssessment {
    pub(super) task: crate::TaskSummary,
    pub(super) repos: Vec<CleanupRepoAssessment>,
    pub(super) has_repos: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct CleanupRepoAssessment {
    pub(super) name: String,
    pub(super) reasons: Vec<String>,
    pub(super) status: Option<CleanupRepoStatus>,
    pub(super) dry_run_hook: Option<camino::Utf8PathBuf>,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(super) enum CleanupScanMode {
    #[default]
    ReasonsOnly,
    WithStatus,
}

impl CleanupScanMode {
    pub(super) fn includes_status(self) -> bool {
        matches!(self, Self::WithStatus)
    }
}

impl TaskCleanupAssessment {
    pub(super) fn new(
        task: crate::TaskSummary,
        repos: Vec<CleanupRepoAssessment>,
        has_repos: bool,
    ) -> Self {
        Self {
            task,
            repos,
            has_repos,
        }
    }

    pub(super) fn dry_run_hooks(&self) -> Vec<camino::Utf8PathBuf> {
        self.repos
            .iter()
            .filter_map(|repo| repo.dry_run_hook.clone())
            .collect()
    }

    fn candidate_reasons(&self) -> Vec<String> {
        if !self.has_repos {
            return vec!["No repos".to_string()];
        }
        self.repos
            .iter()
            .flat_map(|repo| {
                repo.reasons
                    .iter()
                    .map(|reason| format!("{}:{reason}", repo.name))
            })
            .collect()
    }

    fn repo_names(&self) -> Vec<String> {
        self.repos.iter().map(|repo| repo.name.clone()).collect()
    }

    fn repo_statuses(&self) -> Vec<CleanupRepoStatus> {
        if !self.has_repos {
            return vec![CleanupRepoStatus::NoRepos];
        }
        self.repos
            .iter()
            .filter_map(|repo| repo.status.clone())
            .collect()
    }

    pub(super) fn candidate(&self) -> Option<CleanupCandidate> {
        let reasons = self.candidate_reasons();
        if reasons.is_empty() {
            return None;
        }
        Some(CleanupCandidate {
            project: self.task.project.clone(),
            task: self.task.task.clone(),
            path: self.task.path.clone(),
            reasons,
        })
    }
}

impl CleanupRepoAssessment {
    pub(super) fn from_check(name: String, check: RepoCleanupCheck) -> Self {
        Self {
            name,
            reasons: check.reasons,
            status: check.status,
            dry_run_hook: check.dry_run_hook,
        }
    }
}

pub(super) fn cleanup_candidate_view(
    assessment: &TaskCleanupAssessment,
) -> Option<CleanupCandidateView> {
    let candidate = assessment.candidate()?;
    let repo_statuses = assessment.repo_statuses();
    let default_selected = is_cleanup_candidate_default_selected(&repo_statuses);
    Some(CleanupCandidateView {
        candidate,
        repos: assessment.repo_names(),
        status: summarize_repo_statuses(repo_statuses),
        default_selected,
    })
}

fn summarize_repo_statuses(repo_statuses: Vec<CleanupRepoStatus>) -> String {
    if repo_statuses.is_empty() {
        return "No repos".to_string();
    }

    let mut ordered_statuses = Vec::new();
    let mut seen: BTreeSet<String> = BTreeSet::new();
    let status_order = [
        "DIRTY",
        "MERGED",
        "CLOSED",
        "OPEN",
        RepoCleanupAssessor::rate_limited_label(),
        "NO_PR",
        "NO_BRANCH",
        "No repos",
    ];
    for status in status_order {
        if repo_statuses
            .iter()
            .map(CleanupRepoStatus::label)
            .any(|value| value == status)
            && seen.insert(status.to_string())
        {
            ordered_statuses.push(status.to_string());
        }
    }
    for status in repo_statuses {
        let label = status.label();
        if label != "DIRTY"
            && label != "MERGED"
            && label != "CLOSED"
            && label != "OPEN"
            && label != RepoCleanupAssessor::rate_limited_label()
            && label != "NO_PR"
            && label != "NO_BRANCH"
            && label != "No repos"
            && seen.insert(label.clone())
        {
            ordered_statuses.push(label);
        }
    }
    if ordered_statuses.is_empty() {
        "NO_PR".to_string()
    } else {
        ordered_statuses.join(", ")
    }
}

fn is_cleanup_candidate_default_selected(repo_statuses: &[CleanupRepoStatus]) -> bool {
    if repo_statuses.is_empty() {
        return false;
    }
    if repo_statuses
        .iter()
        .any(|status| matches!(status, CleanupRepoStatus::NoRepos))
    {
        return true;
    }

    for status in repo_statuses {
        match status {
            CleanupRepoStatus::Merged | CleanupRepoStatus::Closed => {}
            CleanupRepoStatus::Dirty
            | CleanupRepoStatus::Open
            | CleanupRepoStatus::GithubRateLimited
            | CleanupRepoStatus::NoPr
            | CleanupRepoStatus::NoBranch
            | CleanupRepoStatus::NoRepos
            | CleanupRepoStatus::Other(_) => return false,
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::super::cleanup_assessment::CleanupRepoStatus;
    use super::{
        CleanupRepoAssessment, TaskCleanupAssessment, cleanup_candidate_view,
        is_cleanup_candidate_default_selected, summarize_repo_statuses,
    };
    use crate::{CleanupCandidate, TaskSummary};
    use camino::Utf8PathBuf;

    fn task_summary() -> TaskSummary {
        TaskSummary {
            id: "api/setup-ci".to_string(),
            project: "api".to_string(),
            task: "setup-ci".to_string(),
            path: Utf8PathBuf::from("Workspace/api/setup-ci"),
        }
    }

    #[test]
    fn task_cleanup_assessment_without_repos_becomes_candidate() {
        let assessment = TaskCleanupAssessment {
            task: task_summary(),
            repos: Vec::new(),
            has_repos: false,
        };

        assert_eq!(
            assessment.candidate(),
            Some(CleanupCandidate {
                project: "api".to_string(),
                task: "setup-ci".to_string(),
                path: Utf8PathBuf::from("Workspace/api/setup-ci"),
                reasons: vec!["No repos".to_string()],
            })
        );
    }

    #[test]
    fn cleanup_candidate_view_is_derived_from_assessment() {
        let assessment = TaskCleanupAssessment {
            task: task_summary(),
            repos: vec![CleanupRepoAssessment {
                name: "web".to_string(),
                reasons: vec!["MERGED".to_string()],
                status: Some(CleanupRepoStatus::Merged),
                dry_run_hook: None,
            }],
            has_repos: true,
        };

        assert_eq!(
            cleanup_candidate_view(&assessment),
            Some(super::CleanupCandidateView {
                candidate: CleanupCandidate {
                    project: "api".to_string(),
                    task: "setup-ci".to_string(),
                    path: Utf8PathBuf::from("Workspace/api/setup-ci"),
                    reasons: vec!["web:MERGED".to_string()],
                },
                repos: vec!["web".to_string()],
                status: "MERGED".to_string(),
                default_selected: true,
            })
        );
    }

    #[test]
    fn selects_task_with_no_repos() {
        assert!(is_cleanup_candidate_default_selected(&[
            CleanupRepoStatus::NoRepos
        ]));
    }

    #[test]
    fn selects_task_with_all_merged_or_closed() {
        assert!(is_cleanup_candidate_default_selected(&[
            CleanupRepoStatus::Merged,
            CleanupRepoStatus::Closed,
            CleanupRepoStatus::Closed,
        ]));
    }

    #[test]
    fn does_not_select_task_with_dirty_repos() {
        assert!(!is_cleanup_candidate_default_selected(&[
            CleanupRepoStatus::Dirty,
            CleanupRepoStatus::Closed,
        ]));
    }

    #[test]
    fn does_not_select_task_with_open_repos() {
        assert!(!is_cleanup_candidate_default_selected(&[
            CleanupRepoStatus::Open,
            CleanupRepoStatus::Merged,
        ]));
    }

    #[test]
    fn does_not_select_task_with_no_pr() {
        assert!(!is_cleanup_candidate_default_selected(&[
            CleanupRepoStatus::NoPr
        ]));
    }

    #[test]
    fn does_not_select_task_with_github_rate_limited_repo() {
        assert!(!is_cleanup_candidate_default_selected(&[
            CleanupRepoStatus::GithubRateLimited
        ]));
    }

    #[test]
    fn summarizes_github_rate_limited_status_before_no_pr() {
        assert_eq!(
            summarize_repo_statuses(vec![
                CleanupRepoStatus::NoPr,
                CleanupRepoStatus::GithubRateLimited
            ]),
            "GH_RATE_LIMITED, NO_PR"
        );
    }
}
