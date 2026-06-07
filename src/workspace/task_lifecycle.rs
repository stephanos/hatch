use crate::workspace::helpers::run_with_rollback;
use crate::{AppPaths, Error, Result, TaskCreationPlan, TaskSummary};

use super::WorkspaceHookAdapter;
use super::location;
use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone)]
pub(crate) struct TaskLifecycleService {
    core: WorkspaceServiceCore,
}

impl TaskLifecycleService {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn create_from_plan(
        &self,
        paths: &AppPaths,
        plan: TaskCreationPlan,
    ) -> Result<TaskSummary> {
        let project_path = self.core.project_path(paths, &plan.project);
        let hooks = WorkspaceHookAdapter::new(self.core.clone());
        run_with_rollback(&plan.task_directory, || {
            fs_err::create_dir_all(&plan.task_directory).map_err(|source| Error::Io {
                path: plan.task_directory.clone().into_std_path_buf(),
                source,
            })?;
            hooks.run_task_new(paths, &project_path, &plan.task_directory)?;
            hooks.run_task_open(paths, &project_path, &plan.task_directory)?;
            self.mark_recent(paths, &plan.project)?;
            Ok(TaskSummary {
                id: format!("{}/{}", plan.project, plan.task),
                project: plan.project.clone(),
                task: plan.task.clone(),
                path: plan.task_directory.clone(),
            })
        })
    }

    pub(crate) fn open_resolved_task(
        &self,
        paths: &AppPaths,
        task: TaskSummary,
    ) -> Result<TaskSummary> {
        let context = location::task_context_for_task_path(&task.path)?;
        WorkspaceHookAdapter::new(self.core.clone()).run_task_open(
            paths,
            &context.project_path,
            &task.path,
        )?;
        self.mark_recent(paths, &task.project)?;
        Ok(task)
    }

    fn mark_recent(&self, paths: &AppPaths, project: &str) -> Result<()> {
        let mut recent = self.core.store.load_recent_projects(paths)?;
        recent.retain(|existing| existing != project);
        recent.insert(0, project.to_string());
        self.core.store.save_recent_projects(paths, &recent)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use camino::Utf8PathBuf;
    use tempfile::tempdir;

    fn test_lifecycle() -> (TaskLifecycleService, AppPaths, Utf8PathBuf, Utf8PathBuf) {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = Utf8PathBuf::from_path_buf(root.keep())
            .unwrap_or_else(|path| panic!("tempdir path is not valid UTF-8: {}", path.display()));
        let workspace_root = root.join("Workspace");
        let store =
            crate::HatchStore::new(crate::HatchEnvironment::new(Some(workspace_root.clone())));
        let paths = store
            .paths()
            .unwrap_or_else(|error| panic!("failed to load paths: {error}"));
        let service = TaskLifecycleService::new(WorkspaceServiceCore::new(store));

        fs_err::create_dir_all(workspace_root.join("api/.hatch/hooks"))
            .unwrap_or_else(|error| panic!("failed to create project hooks: {error}"));

        let task_log = root.join("task-hooks.log");

        fs_err::write(
            workspace_root.join("api/.hatch/hooks/task_new.sh"),
            format!(
                "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --task-path)\n      task_path=\"$2\"\n      shift 2\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nprintf 'task_new:%s\\n' \"$task_path\" >> '{}'\n",
                task_log
            ),
        )
        .unwrap();
        fs_err::write(
            workspace_root.join("api/.hatch/hooks/task_open.sh"),
            format!(
                "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --task-path)\n      task_path=\"$2\"\n      shift 2\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nprintf 'task_open:%s\\n' \"$task_path\" >> '{}'\nprintf 'opened %s\\n' \"$task_path\"\n",
                task_log
            ),
        )
        .unwrap();

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;

            for path in [
                workspace_root.join("api/.hatch/hooks/task_new.sh"),
                workspace_root.join("api/.hatch/hooks/task_open.sh"),
            ] {
                let mut permissions = fs_err::metadata(&path).unwrap().permissions();
                permissions.set_mode(0o755);
                fs_err::set_permissions(&path, permissions).unwrap();
            }
        }

        (service, paths, workspace_root, task_log)
    }

    #[test]
    fn create_from_plan_runs_task_new_and_task_open_in_order() {
        let (service, paths, workspace_root, task_log) = test_lifecycle();
        let plan = TaskCreationPlan {
            project: "api".to_string(),
            task: "setup-ci".to_string(),
            task_directory: workspace_root.join("api/setup-ci"),
        };

        let summary = service.create_from_plan(&paths, plan).unwrap();

        assert_eq!(summary.id, "api/setup-ci");
        assert_eq!(
            fs_err::read_to_string(task_log).unwrap(),
            format!(
                "task_new:{}\ntask_open:{}\n",
                workspace_root.join("api/setup-ci"),
                workspace_root.join("api/setup-ci"),
            )
        );
    }

    #[test]
    fn create_from_plan_rolls_back_task_directory_when_task_hook_fails() {
        let (service, paths, workspace_root, _) = test_lifecycle();
        fs_err::write(
            workspace_root.join("api/.hatch/hooks/task_new.sh"),
            "#!/usr/bin/env sh\nprintf 'boom\\n' >&2\nexit 1\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let hook_path = workspace_root.join("api/.hatch/hooks/task_new.sh");
            let mut permissions = fs_err::metadata(&hook_path).unwrap().permissions();
            permissions.set_mode(0o755);
            fs_err::set_permissions(&hook_path, permissions).unwrap();
        }

        let plan = TaskCreationPlan {
            project: "api".to_string(),
            task: "broken".to_string(),
            task_directory: workspace_root.join("api/broken"),
        };

        let error = service.create_from_plan(&paths, plan).unwrap_err();

        assert!(error.to_string().contains("boom"));
        assert!(!workspace_root.join("api/broken").exists());
    }

    #[test]
    fn open_resolved_task_runs_task_open_and_updates_recent_projects() {
        let (service, paths, workspace_root, task_log) = test_lifecycle();
        fs_err::create_dir_all(workspace_root.join("api/follow-up")).unwrap();

        let summary = service
            .open_resolved_task(
                &paths,
                TaskSummary {
                    id: "api/follow-up".to_string(),
                    project: "api".to_string(),
                    task: "follow-up".to_string(),
                    path: workspace_root.join("api/follow-up"),
                },
            )
            .unwrap();

        assert_eq!(summary.id, "api/follow-up");
        assert_eq!(
            fs_err::read_to_string(task_log).unwrap(),
            format!("task_open:{}\n", workspace_root.join("api/follow-up"))
        );
        assert_eq!(
            service.core.store.load_recent_projects(&paths).unwrap(),
            vec!["api".to_string()]
        );
    }
}
