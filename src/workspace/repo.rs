use crate::{AddRepoRequest, AppPaths, Result};
use camino::Utf8Path;

use super::helpers::validate_identifier;
use super::location::{self, WorkspaceLocation};
use super::materialize::RepoMaterializationPlan;
use super::repo_lifecycle::RepoLifecycleService;
use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone)]
pub(crate) struct RepoOperationsService {
    core: WorkspaceServiceCore,
}

struct RepoCheckoutPlanRequest<'a> {
    paths: &'a AppPaths,
    repo_input: &'a str,
    task_path: &'a Utf8Path,
    checkout_dir: Option<String>,
    base_branch_override: Option<String>,
    force: bool,
}

impl RepoOperationsService {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn add_repo(&self, paths: &AppPaths, request: AddRepoRequest) -> Result<()> {
        let plan = self.plan_repo_checkout(RepoCheckoutPlanRequest {
            paths,
            repo_input: &request.repo,
            task_path: &request.task_path,
            checkout_dir: request.checkout_dir,
            base_branch_override: request.base_branch,
            force: request.force,
        })?;
        self.execute_repo_checkout(plan)
    }

    fn plan_repo_checkout(
        &self,
        request: RepoCheckoutPlanRequest<'_>,
    ) -> Result<RepoMaterializationPlan> {
        let (project_path, task_path) =
            match location::resolve_workspace_location(request.paths, request.task_path)? {
                WorkspaceLocation::Task {
                    project_path,
                    task_path,
                }
                | WorkspaceLocation::Repo {
                    project_path,
                    task_path,
                    ..
                } => (project_path, task_path),
                WorkspaceLocation::Workspace { .. } | WorkspaceLocation::Project { .. } => {
                    return Err(crate::Error::Message(
                        "repo new must be run from within a task folder".to_string(),
                    ));
                }
            };
        let spec = self
            .core
            .repo_resolver
            .resolve_repo_spec_from_task(request.repo_input, &task_path)?;
        let checkout_dir = match request.checkout_dir {
            Some(value) => validate_identifier("checkout directory name", &value)?,
            None => spec.repo.clone(),
        };
        let repo_path = task_path.join(checkout_dir);
        let base_branch = request.base_branch_override;
        Ok(RepoMaterializationPlan {
            paths: request.paths.clone(),
            project_path,
            task_path,
            clone_url: spec.clone_url,
            repo_path,
            base_branch,
            force: request.force,
        })
    }

    fn execute_repo_checkout(&self, plan: RepoMaterializationPlan) -> Result<()> {
        let outcome = RepoLifecycleService::new(self.core.clone()).materialize_repo(plan)?;
        crate::hooks::print_hook_outcome(&outcome);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use camino::Utf8PathBuf;
    use tempfile::tempdir;

    fn test_service() -> (RepoOperationsService, AppPaths, Utf8PathBuf) {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = Utf8PathBuf::from_path_buf(root.keep())
            .unwrap_or_else(|path| panic!("tempdir path is not valid UTF-8: {}", path.display()));
        let workspace_root = root.join("Workspace");
        let store =
            crate::HatchStore::new(crate::HatchEnvironment::new(Some(workspace_root.clone())));
        let paths = store
            .paths()
            .unwrap_or_else(|error| panic!("failed to load paths: {error}"));
        fs_err::create_dir_all(&paths.workspace_root)
            .unwrap_or_else(|error| panic!("failed to create workspace root: {error}"));
        fs_err::create_dir_all(&paths.hooks_directory)
            .unwrap_or_else(|error| panic!("failed to create hooks directory: {error}"));
        let service = RepoOperationsService::new(WorkspaceServiceCore::new(store));
        (service, paths, workspace_root)
    }

    #[test]
    fn plan_repo_checkout_prefers_explicit_branch_override() {
        let (service, paths, workspace_root) = test_service();
        let task_path = workspace_root.join("api").join("setup-ci");
        fs_err::create_dir_all(task_path.clone())
            .unwrap_or_else(|error| panic!("failed to create task path: {error}"));
        fs_err::create_dir_all(workspace_root.join("api/.hatch"))
            .unwrap_or_else(|error| panic!("failed to create project hatch dir: {error}"));
        let project_path = Utf8PathBuf::from_path_buf(
            workspace_root
                .join("api")
                .canonicalize()
                .unwrap_or_else(|error| panic!("failed to canonicalize project path: {error}")),
        )
        .unwrap_or_else(|path| panic!("project path is not valid UTF-8: {}", path.display()));

        let plan = service
            .plan_repo_checkout(RepoCheckoutPlanRequest {
                paths: &paths,
                repo_input: "acme/web",
                task_path: &task_path,
                checkout_dir: None,
                base_branch_override: Some("release".to_string()),
                force: true,
            })
            .unwrap_or_else(|error| panic!("expected repo checkout plan: {error}"));

        assert_eq!(plan.project_path, project_path);
        assert_eq!(plan.task_path, task_path.canonicalize_utf8().unwrap());
        assert_eq!(plan.clone_url, "https://github.com/acme/web.git");
        assert_eq!(plan.repo_path, plan.task_path.join("web"));
        assert_eq!(plan.base_branch.as_deref(), Some("release"));
        assert!(plan.force);
    }
}
