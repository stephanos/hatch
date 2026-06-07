use crate::workspace::helpers::validate_identifier;
use crate::{AddRepoRequest, AppPaths, ProjectSummary, Result, TaskCreateRequest};

mod cleanup;
mod cleanup_assessment;
mod cleanup_plan;
mod helpers;
mod hook_adapter;
mod lifecycle;
mod location;
mod materialize;
mod project;
mod query;
mod repo;
mod repo_lifecycle;
mod shared;
mod task;
mod task_lifecycle;

pub(crate) use cleanup::CleanupService;
pub use cleanup_plan::CleanupCandidateView;
pub(crate) use hook_adapter::WorkspaceHookAdapter;
pub(crate) use lifecycle::WorkspaceLifecycleService;
pub(crate) use project::ProjectService;
pub(crate) use repo::RepoOperationsService;
pub(crate) use shared::WorkspaceServiceCore;
pub(crate) use task::TaskService;
use task_lifecycle::TaskLifecycleService;

#[derive(Debug, Clone)]
pub struct WorkspaceService {
    core: WorkspaceServiceCore,
    lifecycle: WorkspaceLifecycleService,
    project: ProjectService,
    repo: RepoOperationsService,
    task: TaskService,
    task_lifecycle: TaskLifecycleService,
    cleanup: CleanupService,
}

impl WorkspaceService {
    pub fn from_env() -> Result<Self> {
        Ok(Self::new(crate::HatchStore::from_env()?))
    }

    pub fn new(store: crate::HatchStore) -> Self {
        let core = WorkspaceServiceCore::new(store);
        let project = ProjectService::new(core.clone());
        let repo = RepoOperationsService::new(core.clone());
        let task = TaskService::new(core.clone());
        let task_lifecycle = TaskLifecycleService::new(core.clone());
        let cleanup = CleanupService::new(core.clone(), task.clone());
        let lifecycle = WorkspaceLifecycleService::new(core.clone());
        Self {
            core,
            lifecycle,
            project,
            repo,
            task,
            task_lifecycle,
            cleanup,
        }
    }

    pub fn paths(&self) -> Result<AppPaths> {
        self.core.store.paths()
    }

    pub fn list_projects(&self, paths: &AppPaths) -> Result<Vec<ProjectSummary>> {
        self.project.list_projects(paths)
    }

    pub fn list_projects_in_workspace(&self) -> Result<Vec<ProjectSummary>> {
        let paths = self.paths()?;
        self.project.list_projects(&paths)
    }

    pub fn resolve_project_query(&self, paths: &AppPaths, query: &str) -> Result<ProjectSummary> {
        self.project.resolve_project_query(paths, query)
    }

    pub fn create_project(
        &self,
        paths: &AppPaths,
        request: crate::ProjectCreateRequest,
    ) -> Result<ProjectSummary> {
        self.project.create_project(paths, request)
    }

    pub fn create_project_in_workspace(
        &self,
        request: crate::ProjectCreateRequest,
    ) -> Result<ProjectSummary> {
        let paths = self.paths()?;
        self.project.create_project(&paths, request)
    }

    pub fn delete_project(&self, paths: &AppPaths, query: &str) -> Result<ProjectSummary> {
        self.project.delete_project(paths, query)
    }

    pub fn create_workspace(&self, force: bool) -> Result<()> {
        self.lifecycle.create_workspace(force)
    }

    pub fn list_tasks(&self, paths: &AppPaths) -> Result<Vec<crate::TaskSummary>> {
        self.task.list_tasks(paths)
    }

    pub fn create_task(
        &self,
        paths: &AppPaths,
        request: TaskCreateRequest,
    ) -> Result<crate::TaskSummary> {
        let TaskCreateRequest { project, task } = request;
        let task = validate_identifier("task name", &task)?;
        let project_path = self.core.project_path(paths, &project);
        self.core.ensure_project_exists(&project_path)?;
        let task_path = self.core.task_path(paths, &project, &task);
        if task_path.exists() {
            return self.task_lifecycle.open_resolved_task(
                paths,
                crate::TaskSummary {
                    id: format!("{}/{}", project, task),
                    project,
                    task,
                    path: task_path,
                },
            );
        }
        let plan = self.task.plan_task_creation(paths, &project, &task)?;
        self.task_lifecycle.create_from_plan(paths, plan)
    }

    pub fn create_task_in_workspace(
        &self,
        request: TaskCreateRequest,
    ) -> Result<crate::TaskSummary> {
        let paths = self.paths()?;
        self.create_task(&paths, request)
    }

    pub fn open_task_by_query(&self, paths: &AppPaths, query: &str) -> Result<crate::TaskSummary> {
        let task = self.task.resolve_task_query(paths, query)?;
        self.task_lifecycle.open_resolved_task(paths, task)
    }

    pub fn open_task_by_query_in_workspace(&self, query: &str) -> Result<crate::TaskSummary> {
        let paths = self.paths()?;
        self.open_task_by_query(&paths, query)
    }

    pub fn delete_task(&self, paths: &AppPaths, query: &str) -> Result<crate::TaskSummary> {
        self.task.delete_task(paths, query)
    }

    pub fn delete_task_in_workspace(&self, query: &str) -> Result<crate::TaskSummary> {
        let paths = self.paths()?;
        self.task.delete_task(&paths, query)
    }

    pub fn list_tasks_in_workspace(&self) -> Result<Vec<crate::TaskSummary>> {
        let paths = self.paths()?;
        self.task.list_tasks(&paths)
    }

    pub fn project_delete_preview_in_workspace(
        &self,
        query: &str,
    ) -> Result<(ProjectSummary, Vec<crate::TaskSummary>)> {
        let paths = self.paths()?;
        let project = self.project.resolve_project_query(&paths, query)?;
        let tasks = self
            .task
            .list_tasks(&paths)?
            .into_iter()
            .filter(|task| task.project == project.name)
            .collect::<Vec<_>>();
        Ok((project, tasks))
    }

    pub fn delete_project_in_workspace(&self, project: &str) -> Result<ProjectSummary> {
        let paths = self.paths()?;
        self.project.delete_project(&paths, project)
    }

    pub fn cleanup_candidates_with_view(
        &self,
        paths: &AppPaths,
    ) -> Result<Vec<CleanupCandidateView>> {
        self.cleanup.cleanup_candidates_with_view(paths)
    }

    pub fn cleanup_candidates_with_view_in_workspace(&self) -> Result<Vec<CleanupCandidateView>> {
        let paths = self.paths()?;
        self.cleanup.cleanup_candidates_with_view(&paths)
    }

    pub fn cleanup_candidates_with_view_for_project_in_workspace(
        &self,
        query: &str,
    ) -> Result<Vec<CleanupCandidateView>> {
        let paths = self.paths()?;
        let project = self.project.resolve_project_query(&paths, query)?;
        Ok(self
            .cleanup
            .cleanup_candidates_with_view(&paths)?
            .into_iter()
            .filter(|candidate| candidate.candidate.project == project.name)
            .collect())
    }

    pub fn cleanup_selected_tasks_in_workspace(
        &self,
        candidates: &[crate::CleanupCandidate],
    ) -> Result<Vec<crate::CleanupCandidate>> {
        let paths = self.paths()?;
        self.cleanup.cleanup_selected_tasks(&paths, candidates)
    }

    pub fn add_repo(&self, paths: &AppPaths, request: AddRepoRequest) -> Result<()> {
        self.repo.add_repo(paths, request)
    }

    pub fn add_repo_in_workspace(&self, request: AddRepoRequest) -> Result<()> {
        let paths = self.paths()?;
        self.repo.add_repo(&paths, request)
    }

    pub fn run_workspace_hook_in_workspace(&self, hook: &str, args: Vec<String>) -> Result<()> {
        let paths = self.paths()?;
        let hook = crate::hooks::HookName::from_name(hook)?;
        WorkspaceHookAdapter::new(self.core.clone()).run_workspace_hook(&paths, hook, &args)?;
        Ok(())
    }

    pub fn start_agent_in_workspace(&self, agent: String, args: Vec<String>) -> Result<()> {
        let paths = self.paths()?;
        let current_dir = std::env::current_dir()
            .map_err(|source| crate::Error::Message(format!("failed to read cwd: {source}")))?;
        let current_dir = camino::Utf8PathBuf::from_path_buf(current_dir).map_err(|path| {
            crate::Error::Message(format!("cwd is not valid UTF-8: {}", path.display()))
        })?;
        let scope = location::resolve_agent_scope(&paths, &current_dir)?;
        WorkspaceHookAdapter::new(self.core.clone()).run_agent_start(
            &paths,
            scope.project_path.as_deref(),
            agent,
            &scope.scope_path,
            args,
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use camino::Utf8PathBuf;
    use std::path::Path;
    use tempfile::tempdir;

    fn test_service() -> (WorkspaceService, Utf8PathBuf, Utf8PathBuf) {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = Utf8PathBuf::from_path_buf(root.keep())
            .unwrap_or_else(|path| panic!("tempdir path is not valid UTF-8: {}", path.display()));
        let workspace_root = root.join("Workspace");
        let task_open_log = root.join("task-open.log");
        let store =
            crate::HatchStore::new(crate::HatchEnvironment::new(Some(workspace_root.clone())));
        let service = WorkspaceService::new(store);
        service
            .create_workspace(false)
            .unwrap_or_else(|error| panic!("failed to create workspace: {error}"));
        let task_open_hook = workspace_root.join(".hatch/hooks/task_open.sh");
        write_executable(
            task_open_hook.as_std_path(),
            &format!(
                "#!/bin/sh\n\
task_path=\"\"\n\
while [ \"$#\" -gt 0 ]; do\n\
  case \"$1\" in\n\
    --task-path)\n\
      task_path=\"$2\"\n\
      shift 2\n\
      ;;\n\
    *)\n\
      shift\n\
      ;;\n\
  esac\n\
done\n\
printf '%s\\n' \"$task_path\" > '{}'\n",
                task_open_log
            ),
        );
        (service, workspace_root, task_open_log)
    }

    fn write_executable(path: &Path, script: &str) {
        fs_err::write(path, script)
            .unwrap_or_else(|error| panic!("failed to write script {}: {error}", path.display()));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;

            let metadata = fs_err::metadata(path).unwrap_or_else(|error| {
                panic!("failed to read metadata for {}: {error}", path.display())
            });
            let mut permissions = metadata.permissions();
            permissions.set_mode(0o755);
            fs_err::set_permissions(path, permissions).unwrap_or_else(|error| {
                panic!("failed to set permissions for {}: {error}", path.display())
            });
        }
    }

    #[test]
    fn create_project_in_workspace_loads_paths() {
        let (service, workspace_root, _) = test_service();

        let project = service
            .create_project_in_workspace(crate::ProjectCreateRequest {
                name: "api".to_string(),
                force: false,
            })
            .unwrap_or_else(|error| panic!("failed to create project in workspace: {error}"));

        assert_eq!(project.path, workspace_root.join("api"));
        assert!(workspace_root.join("api/.hatch/hooks/task_new.sh").exists());
    }

    #[test]
    fn open_task_by_query_in_workspace_loads_paths() {
        let (service, workspace_root, task_open_log) = test_service();
        let project_root = workspace_root.join("api");
        fs_err::create_dir_all(project_root.join(".hatch"))
            .unwrap_or_else(|error| panic!("failed to create project hatch dir: {error}"));
        fs_err::create_dir_all(project_root.join("setup-ci"))
            .unwrap_or_else(|error| panic!("failed to create task dir: {error}"));

        let task = service
            .open_task_by_query_in_workspace("setup")
            .unwrap_or_else(|error| panic!("failed to open task by query in workspace: {error}"));

        assert_eq!(task.id, "api/setup-ci");
        assert_eq!(task.path, project_root.join("setup-ci"));
        assert_eq!(
            fs_err::read_to_string(&task_open_log)
                .unwrap_or_else(|error| panic!("failed to read task open log: {error}")),
            format!("{}\n", project_root.join("setup-ci"))
        );
    }
}
