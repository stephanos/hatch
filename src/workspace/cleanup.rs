use super::cleanup_assessment::RepoCleanupAssessor;
use super::cleanup_plan::{
    CleanupCandidateView, CleanupRepoAssessment, CleanupScanMode, TaskCleanupAssessment,
    cleanup_candidate_view,
};
use super::repo_lifecycle::RepoLifecycleService;
use super::shared::WorkspaceServiceCore;
use super::task::TaskService;
use crate::{AppPaths, CleanupCandidate, Error, Result};
use rayon::{ThreadPoolBuilder, prelude::*};

const CLEANUP_SCAN_THREADS: usize = 4;

#[derive(Debug, Clone)]
pub(crate) struct CleanupService {
    core: WorkspaceServiceCore,
    task: TaskService,
}

fn print_batched_hook_statuses(scans: &[Result<TaskCleanupAssessment>]) {
    for scan in scans.iter().filter_map(|scan| scan.as_ref().ok()) {
        for hook_file in scan.dry_run_hooks() {
            crate::terminal::print_hook_status(hook_file);
        }
    }
}

fn cleanup_scan_pool() -> Result<rayon::ThreadPool> {
    let threads = std::thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .clamp(1, CLEANUP_SCAN_THREADS);
    ThreadPoolBuilder::new()
        .num_threads(threads)
        .build()
        .map_err(|source| Error::Message(format!("failed to start cleanup scan pool: {source}")))
}

impl CleanupService {
    pub(crate) fn new(core: WorkspaceServiceCore, task: TaskService) -> Self {
        Self { core, task }
    }

    pub(crate) fn cleanup_candidates_with_view(
        &self,
        paths: &AppPaths,
    ) -> Result<Vec<CleanupCandidateView>> {
        Ok(self
            .cleanup_assessments(paths, CleanupScanMode::WithStatus)?
            .into_iter()
            .filter_map(|assessment| cleanup_candidate_view(&assessment))
            .collect())
    }

    fn cleanup_assessments(
        &self,
        paths: &AppPaths,
        mode: CleanupScanMode,
    ) -> Result<Vec<TaskCleanupAssessment>> {
        let tasks = self.task.list_tasks(paths)?;
        let pool = cleanup_scan_pool()?;
        let scans = pool.install(|| {
            tasks
                .into_par_iter()
                .map(|task| self.assess_task_cleanup(paths, task, mode))
                .collect::<Vec<_>>()
        });
        print_batched_hook_statuses(&scans);
        scans.into_iter().collect()
    }

    fn assess_task_cleanup(
        &self,
        paths: &AppPaths,
        task: crate::TaskSummary,
        mode: CleanupScanMode,
    ) -> Result<TaskCleanupAssessment> {
        let task_repos = self.core.discovery.list_task_repos(&task.path)?;
        let has_repos = !task_repos.is_empty();
        let assessor = RepoCleanupAssessor::new(self.core.clone());
        let repos = task_repos
            .into_par_iter()
            .map(|repo| {
                let check = assessor.assess_repo_cleanup(paths, &task, &repo.path, mode)?;
                Ok(CleanupRepoAssessment::from_check(repo.name, check))
            })
            .collect::<Vec<Result<_>>>()
            .into_iter()
            .collect::<Result<Vec<_>>>()?;
        Ok(TaskCleanupAssessment::new(task, repos, has_repos))
    }

    pub(crate) fn cleanup_selected_tasks(
        &self,
        paths: &AppPaths,
        candidates: &[CleanupCandidate],
    ) -> Result<Vec<CleanupCandidate>> {
        for candidate in candidates {
            self.cleanup_repos(&candidate.path, paths)?;
            self.core.delete_task_directory(&candidate.path)?;
        }
        Ok(candidates.to_vec())
    }

    fn cleanup_repos(&self, task_path: &camino::Utf8Path, paths: &AppPaths) -> Result<()> {
        if !task_path.is_dir() {
            return Ok(());
        }
        let lifecycle = RepoLifecycleService::new(self.core.clone());
        for repo in self.core.discovery.list_task_repos(task_path)? {
            lifecycle.cleanup_repo(paths, task_path, &repo.path)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::super::cleanup_assessment::is_github_rate_limited_error;
    use crate::Error;

    #[test]
    fn detects_github_rate_limit_errors() {
        assert!(is_github_rate_limited_error(&Error::Message(
            "HTTP 429: API rate limit exceeded".to_string()
        )));
        assert!(is_github_rate_limited_error(&Error::Message(
            "secondary rate limit exceeded".to_string()
        )));
        assert!(!is_github_rate_limited_error(&Error::Message(
            "could not find pull request".to_string()
        )));
    }
}
