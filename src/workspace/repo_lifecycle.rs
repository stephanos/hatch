use crate::hooks::HookOutcome;
use crate::{AppPaths, Result};
use camino::Utf8Path;

use super::cleanup_assessment::RepoCleanupAssessor;
use super::hook_adapter::{RepoDeleteHook, WorkspaceHookAdapter};
use super::location;
use super::materialize::{RepoMaterializationPlan, RepoMaterializationService};
use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone)]
pub(crate) struct RepoLifecycleService {
    core: WorkspaceServiceCore,
}

impl RepoLifecycleService {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn materialize_repo(&self, plan: RepoMaterializationPlan) -> Result<HookOutcome> {
        RepoMaterializationService::new(self.core.clone()).materialize_repo(plan)
    }

    pub(crate) fn cleanup_repo(
        &self,
        paths: &AppPaths,
        task_path: &Utf8Path,
        repo_path: &Utf8Path,
    ) -> Result<()> {
        RepoCleanupAssessor::new(self.core.clone()).cleanup_remote_branch_for_repo(repo_path)?;
        let project_path = location::project_path_for_task_path(task_path)?;
        WorkspaceHookAdapter::new(self.core.clone()).run_repo_delete(RepoDeleteHook {
            paths,
            project_path: &project_path,
            task_path,
            repo_path,
        })?;
        Ok(())
    }
}
