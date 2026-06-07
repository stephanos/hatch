use crate::hooks::HookOutcome;
use crate::workspace::helpers::run_with_rollback;
use crate::{AppPaths, Error, Result};
use camino::Utf8PathBuf;

use super::hook_adapter::{RepoNewHook, WorkspaceHookAdapter};
use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct RepoMaterializationPlan {
    pub(crate) paths: AppPaths,
    pub(crate) project_path: Utf8PathBuf,
    pub(crate) task_path: Utf8PathBuf,
    pub(crate) clone_url: String,
    pub(crate) repo_path: Utf8PathBuf,
    pub(crate) base_branch: Option<String>,
    pub(crate) force: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct RepoMaterializationService {
    core: WorkspaceServiceCore,
}

impl RepoMaterializationService {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn materialize_repo(&self, plan: RepoMaterializationPlan) -> Result<HookOutcome> {
        if plan.repo_path.exists() {
            if plan.force {
                fs_err::remove_dir_all(&plan.repo_path).map_err(|source| Error::Io {
                    path: plan.repo_path.clone().into_std_path_buf(),
                    source,
                })?;
            } else {
                let checkout_dir = plan
                    .repo_path
                    .file_name()
                    .unwrap_or(plan.repo_path.as_str());
                return Err(Error::Message(format!(
                    "repo checkout directory '{checkout_dir}' already exists at {}",
                    plan.repo_path
                )));
            }
        }
        run_with_rollback(&plan.repo_path, || {
            fs_err::create_dir_all(&plan.repo_path).map_err(|source| Error::Io {
                path: plan.repo_path.clone().into_std_path_buf(),
                source,
            })?;
            WorkspaceHookAdapter::new(self.core.clone()).run_required_repo_new(RepoNewHook {
                paths: &plan.paths,
                project_path: &plan.project_path,
                task_path: &plan.task_path,
                repo_path: &plan.repo_path,
                clone_url: &plan.clone_url,
                base_branch: &plan.base_branch,
            })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::{RepoMaterializationPlan, RepoMaterializationService};
    use crate::hooks::HookOutcome;
    use crate::workspace::WorkspaceServiceCore;
    use camino::Utf8PathBuf;
    use tempfile::tempdir;

    fn test_materializer() -> (
        RepoMaterializationService,
        crate::AppPaths,
        Utf8PathBuf,
        Utf8PathBuf,
    ) {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = Utf8PathBuf::from_path_buf(root.keep())
            .unwrap_or_else(|path| panic!("tempdir path is not valid UTF-8: {}", path.display()));
        let workspace_root = root.join("Workspace");
        let store =
            crate::HatchStore::new(crate::HatchEnvironment::new(Some(workspace_root.clone())));
        let paths = store
            .paths()
            .unwrap_or_else(|error| panic!("failed to load paths: {error}"));
        fs_err::create_dir_all(paths.hooks_directory.clone())
            .unwrap_or_else(|error| panic!("failed to create hooks dir: {error}"));
        let task_root = workspace_root.join("api/setup-ci");
        fs_err::create_dir_all(&task_root)
            .unwrap_or_else(|error| panic!("failed to create task dir: {error}"));
        fs_err::create_dir_all(workspace_root.join("api/.hatch"))
            .unwrap_or_else(|error| panic!("failed to create project hatch dir: {error}"));
        let hook_log = root.join("repo-new.log");
        fs_err::write(
            paths.hooks_directory.join("repo_new.sh"),
            format!(
                "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --repo-path)\n      repo_path=\"$2\"\n      shift 2\n      ;;\n    --clone-url)\n      clone_url=\"$2\"\n      shift 2\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nprintf '%s\\n' \"$clone_url\" > \"$repo_path/.clone_url\"\nprintf 'hook\\n' > '{}'\n",
                hook_log
            ),
        )
        .unwrap_or_else(|error| panic!("failed to write repo_new hook: {error}"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;

            let hook_path = paths.hooks_directory.join("repo_new.sh");
            let mut permissions = fs_err::metadata(&hook_path)
                .unwrap_or_else(|error| panic!("failed to stat {hook_path}: {error}"))
                .permissions();
            permissions.set_mode(0o755);
            fs_err::set_permissions(&hook_path, permissions)
                .unwrap_or_else(|error| panic!("failed to chmod {hook_path}: {error}"));
        }
        (
            RepoMaterializationService::new(WorkspaceServiceCore::new(store)),
            paths,
            task_root,
            hook_log,
        )
    }

    #[test]
    fn materialize_repo_runs_repo_new_hook_for_a_resolved_plan() {
        let (service, paths, task_root, hook_log) = test_materializer();
        let plan = RepoMaterializationPlan {
            paths: paths.clone(),
            project_path: task_root
                .parent()
                .unwrap_or_else(|| panic!("task root should have project parent"))
                .to_path_buf(),
            task_path: task_root.clone(),
            clone_url: "https://github.com/acme/web.git".to_string(),
            repo_path: task_root.join("web"),
            base_branch: Some("main".to_string()),
            force: false,
        };

        let outcome = service.materialize_repo(plan).unwrap();

        assert!(matches!(
            outcome,
            HookOutcome::RanSilent { .. } | HookOutcome::RanWithOutput { .. }
        ));
        assert_eq!(
            fs_err::read_to_string(task_root.join("web/.clone_url"))
                .unwrap_or_else(|error| panic!("failed to read clone marker: {error}")),
            "https://github.com/acme/web.git\n"
        );
        assert!(hook_log.exists());
    }

    #[test]
    fn materialize_repo_refuses_existing_destination_without_force() {
        let (service, paths, task_root, _) = test_materializer();
        fs_err::create_dir_all(task_root.join("web"))
            .unwrap_or_else(|error| panic!("failed to create repo dir: {error}"));
        let plan = RepoMaterializationPlan {
            paths,
            project_path: task_root
                .parent()
                .unwrap_or_else(|| panic!("task root should have project parent"))
                .to_path_buf(),
            task_path: task_root.clone(),
            clone_url: "https://github.com/acme/web.git".to_string(),
            repo_path: task_root.join("web"),
            base_branch: None,
            force: false,
        };

        let error = service.materialize_repo(plan).unwrap_err();

        let error = error.to_string();
        assert!(error.contains("repo checkout directory 'web'"));
        assert!(error.contains(&task_root.join("web").to_string()));
    }

    #[test]
    fn materialize_repo_requires_repo_new_hook() {
        let (service, paths, task_root, _) = test_materializer();
        let hook_path = paths.hooks_directory.join("repo_new.sh");
        fs_err::remove_file(&hook_path)
            .unwrap_or_else(|error| panic!("failed to remove repo_new hook: {error}"));
        let repo_path = task_root.join("web");
        let plan = RepoMaterializationPlan {
            paths,
            project_path: task_root
                .parent()
                .unwrap_or_else(|| panic!("task root should have project parent"))
                .to_path_buf(),
            task_path: task_root.clone(),
            clone_url: "https://github.com/acme/web.git".to_string(),
            repo_path: repo_path.clone(),
            base_branch: None,
            force: false,
        };

        let error = service.materialize_repo(plan).unwrap_err();

        assert!(error.to_string().contains("repo_new hook not found"));
        assert!(!repo_path.exists());
    }
}
