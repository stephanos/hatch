use crate::{AppPaths, Result};
use camino::{Utf8Path, Utf8PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TaskContext {
    pub(crate) task: crate::TaskSummary,
    pub(crate) project_path: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AgentScope {
    pub(crate) project_path: Option<Utf8PathBuf>,
    pub(crate) scope_path: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum WorkspaceLocation {
    Workspace {
        workspace_root: Utf8PathBuf,
    },
    Project {
        project_path: Utf8PathBuf,
    },
    Task {
        project_path: Utf8PathBuf,
        task_path: Utf8PathBuf,
    },
    Repo {
        project_path: Utf8PathBuf,
        task_path: Utf8PathBuf,
        repo_path: Utf8PathBuf,
    },
}

pub(crate) fn resolve_agent_scope(paths: &AppPaths, current_dir: &Utf8Path) -> Result<AgentScope> {
    match resolve_workspace_location(paths, current_dir)? {
        WorkspaceLocation::Workspace { .. } => Err(crate::Error::Message(
            "agent start must be run from inside a Hatch project, task, or repo".to_string(),
        )),
        WorkspaceLocation::Project { project_path } => Ok(AgentScope {
            project_path: Some(project_path.clone()),
            scope_path: project_path,
        }),
        WorkspaceLocation::Task {
            project_path,
            task_path,
        } => Ok(AgentScope {
            project_path: Some(project_path),
            scope_path: task_path,
        }),
        WorkspaceLocation::Repo {
            project_path,
            task_path: _,
            repo_path,
        } => Ok(AgentScope {
            project_path: Some(project_path),
            scope_path: repo_path,
        }),
    }
}

pub(crate) fn resolve_workspace_location(
    paths: &AppPaths,
    current_dir: &Utf8Path,
) -> Result<WorkspaceLocation> {
    let workspace_root = canonical_utf8(&paths.workspace_root)?;
    let current_dir = canonical_utf8(current_dir)?;
    if current_dir != workspace_root && !current_dir.starts_with(&workspace_root) {
        return Err(crate::Error::Message(
            "agent start must be run from inside a Hatch workspace".to_string(),
        ));
    }
    let project_path = current_dir
        .ancestors()
        .take_while(|candidate| *candidate != workspace_root)
        .find(|candidate| {
            candidate.parent() == Some(workspace_root.as_path())
                && candidate
                    .join(crate::environment::PROJECT_MARKER_DIRECTORY)
                    .is_dir()
        })
        .map(Utf8Path::to_path_buf);
    let Some(project_path) = project_path else {
        return Ok(WorkspaceLocation::Workspace { workspace_root });
    };
    let task_path = current_dir
        .ancestors()
        .take_while(|candidate| *candidate != project_path)
        .find(|candidate| {
            candidate.parent() == Some(project_path.as_path())
                && candidate.file_name() != Some(crate::environment::PROJECT_MARKER_DIRECTORY)
        })
        .map(Utf8Path::to_path_buf);
    Ok(match task_path {
        Some(task_path) => {
            let repo_path = current_dir
                .ancestors()
                .take_while(|candidate| *candidate != task_path)
                .find(|candidate| {
                    candidate.parent() == Some(task_path.as_path())
                        && candidate.join(".git").is_dir()
                })
                .map(Utf8Path::to_path_buf);
            match repo_path {
                Some(repo_path) => WorkspaceLocation::Repo {
                    project_path,
                    task_path,
                    repo_path,
                },
                None => WorkspaceLocation::Task {
                    project_path,
                    task_path,
                },
            }
        }
        None => WorkspaceLocation::Project { project_path },
    })
}

pub(crate) fn task_context_for_task_path(task_path: &Utf8Path) -> Result<TaskContext> {
    if !task_path.is_dir() {
        return Err(crate::Error::Message(format!("{task_path} does not exist")));
    }
    let task_path = canonical_utf8(task_path)?;
    let Some(project_path) = task_path.parent() else {
        return Err(crate::Error::Message(format!(
            "{task_path} is not a Hatch task"
        )));
    };
    if !project_path
        .join(crate::environment::PROJECT_MARKER_DIRECTORY)
        .exists()
    {
        return Err(crate::Error::Message(format!(
            "{task_path} is not a Hatch task"
        )));
    }
    task_context(project_path, &task_path)
}

pub(crate) fn project_path_for_task_path(task_path: &Utf8Path) -> Result<Utf8PathBuf> {
    task_context_for_task_path(task_path).map(|context| context.project_path)
}

fn task_context(project_path: &Utf8Path, task_path: &Utf8Path) -> Result<TaskContext> {
    let task = task_path.file_name().unwrap_or_default().to_string();
    let project = project_path.file_name().unwrap_or_default().to_string();
    Ok(TaskContext {
        task: crate::TaskSummary {
            id: format!("{project}/{task}"),
            project,
            task,
            path: task_path.to_path_buf(),
        },
        project_path: project_path.to_path_buf(),
    })
}

fn canonical_utf8(path: &Utf8Path) -> Result<Utf8PathBuf> {
    let canonical = path.canonicalize().map_err(|source| crate::Error::Io {
        path: path.to_path_buf().into_std_path_buf(),
        source,
    })?;
    Utf8PathBuf::from_path_buf(canonical).map_err(|path| {
        crate::Error::Message(format!("path is not valid UTF-8: {}", path.display()))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn test_paths(root: &Utf8Path) -> AppPaths {
        AppPaths {
            workspace_root: root.to_path_buf(),
            hatch_root: root.join(".hatch"),
            hooks_directory: root.join(".hatch/hooks"),
            state_directory: root.join(".hatch/state"),
            cache_directory: root.join(".hatch/cache"),
            repos_directory: root.join(".hatch/repos"),
        }
    }

    #[test]
    fn resolves_task_scope_from_nested_path() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let workspace = Utf8PathBuf::from_path_buf(temp.path().join("Workspace"))
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()));
        let nested = workspace.join("api/setup-ci/notes/src");
        fs_err::create_dir_all(workspace.join("api/.hatch"))
            .unwrap_or_else(|error| panic!("failed to create project marker: {error}"));
        fs_err::create_dir_all(&nested)
            .unwrap_or_else(|error| panic!("failed to create nested path: {error}"));

        let scope = resolve_agent_scope(&test_paths(&workspace), &nested)
            .unwrap_or_else(|error| panic!("failed to resolve agent scope: {error}"));

        assert_eq!(
            scope.project_path,
            Some(workspace.join("api").canonicalize_utf8().unwrap())
        );
        assert_eq!(
            scope.scope_path,
            workspace.join("api/setup-ci").canonicalize_utf8().unwrap()
        );
    }

    #[test]
    fn resolves_repo_scope_from_nested_path() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let workspace = Utf8PathBuf::from_path_buf(temp.path().join("Workspace"))
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()));
        let nested = workspace.join("api/setup-ci/repo/src");
        fs_err::create_dir_all(workspace.join("api/.hatch"))
            .unwrap_or_else(|error| panic!("failed to create project marker: {error}"));
        fs_err::create_dir_all(workspace.join("api/setup-ci/repo/.git"))
            .unwrap_or_else(|error| panic!("failed to create repo marker: {error}"));
        fs_err::create_dir_all(&nested)
            .unwrap_or_else(|error| panic!("failed to create nested path: {error}"));

        let scope = resolve_agent_scope(&test_paths(&workspace), &nested)
            .unwrap_or_else(|error| panic!("failed to resolve agent scope: {error}"));

        assert_eq!(
            scope.project_path,
            Some(workspace.join("api").canonicalize_utf8().unwrap())
        );
        assert_eq!(
            scope.scope_path,
            workspace
                .join("api/setup-ci/repo")
                .canonicalize_utf8()
                .unwrap()
        );
    }

    #[test]
    fn rejects_workspace_scope_for_agent_start() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let workspace = Utf8PathBuf::from_path_buf(temp.path().join("Workspace"))
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()));
        fs_err::create_dir_all(&workspace)
            .unwrap_or_else(|error| panic!("failed to create workspace: {error}"));

        let error = resolve_agent_scope(&test_paths(&workspace), &workspace)
            .unwrap_err()
            .to_string();

        assert!(error.contains("must be run from inside a Hatch project, task, or repo"));
    }

    #[test]
    fn resolves_workspace_location_from_project_path() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let workspace = Utf8PathBuf::from_path_buf(temp.path().join("Workspace"))
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()));
        let project = workspace.join("api");
        fs_err::create_dir_all(project.join(".hatch"))
            .unwrap_or_else(|error| panic!("failed to create project marker: {error}"));

        let location = resolve_workspace_location(&test_paths(&workspace), &project)
            .unwrap_or_else(|error| panic!("failed to resolve workspace location: {error}"));

        assert_eq!(
            location,
            WorkspaceLocation::Project {
                project_path: project.canonicalize_utf8().unwrap()
            }
        );
    }

    #[test]
    fn rejects_paths_outside_workspace() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = Utf8PathBuf::from_path_buf(temp.path().to_path_buf())
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()));
        let workspace = root.join("Workspace");
        let outside = root.join("outside");
        fs_err::create_dir_all(&workspace)
            .unwrap_or_else(|error| panic!("failed to create workspace: {error}"));
        fs_err::create_dir_all(&outside)
            .unwrap_or_else(|error| panic!("failed to create outside path: {error}"));

        let error = resolve_agent_scope(&test_paths(&workspace), &outside)
            .unwrap_err()
            .to_string();

        assert!(error.contains("must be run from inside a Hatch workspace"));
    }

    #[test]
    fn rejects_non_task_path_for_exact_task_context() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let workspace = Utf8PathBuf::from_path_buf(temp.path().join("Workspace"))
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()));
        let repo = workspace.join("api/setup-ci/repo");
        fs_err::create_dir_all(workspace.join("api/.hatch"))
            .unwrap_or_else(|error| panic!("failed to create project marker: {error}"));
        fs_err::create_dir_all(&repo)
            .unwrap_or_else(|error| panic!("failed to create repo path: {error}"));

        let error = task_context_for_task_path(&repo).unwrap_err().to_string();

        assert!(error.contains("is not a Hatch task"));
    }
}
