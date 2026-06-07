use crate::discovery::WorkspaceDiscovery;
use crate::environment::HatchStore;
use crate::git::GitCli;
use crate::github::GithubCli;
use crate::{AppPaths, Error, Result};
use camino::{Utf8Path, Utf8PathBuf};

use crate::repo::RepoService as RepoResolver;

#[derive(Debug, Clone)]
pub(crate) struct WorkspaceServiceCore {
    pub(crate) store: HatchStore,
    pub(crate) discovery: WorkspaceDiscovery,
    pub(crate) hooks: crate::hooks::HookRunner,
    pub(crate) git: GitCli,
    pub(crate) github: GithubCli,
    pub(crate) repo_resolver: RepoResolver,
    task_directory_deletion: TaskDirectoryDeletion,
}

impl WorkspaceServiceCore {
    pub(crate) fn new(store: HatchStore) -> Self {
        let task_directory_deletion = if store.use_direct_task_deletion() {
            TaskDirectoryDeletion::direct()
        } else {
            TaskDirectoryDeletion::platform_default()
        };
        Self {
            store,
            discovery: WorkspaceDiscovery,
            hooks: crate::hooks::HookRunner::default(),
            git: GitCli::default(),
            github: GithubCli::default(),
            repo_resolver: RepoResolver::default(),
            task_directory_deletion,
        }
    }

    pub(crate) fn paths(&self) -> Result<AppPaths> {
        self.store.paths()
    }

    pub(crate) fn project_path(&self, paths: &AppPaths, project: &str) -> Utf8PathBuf {
        paths.workspace_root.join(project)
    }

    pub(crate) fn task_path(&self, paths: &AppPaths, project: &str, task: &str) -> Utf8PathBuf {
        self.project_path(paths, project).join(task)
    }

    pub(crate) fn ensure_project_exists(&self, project_path: &Utf8Path) -> Result<()> {
        if project_path
            .join(crate::environment::PROJECT_MARKER_DIRECTORY)
            .exists()
        {
            Ok(())
        } else {
            Err(Error::Message(format!(
                "project {project_path} does not exist"
            )))
        }
    }

    pub(crate) fn delete_task_directory(&self, path: &Utf8Path) -> Result<()> {
        self.task_directory_deletion.delete_task_directory(path)
    }
}

#[derive(Debug, Clone, Copy)]
struct TaskDirectoryDeletion {
    direct: bool,
}

impl TaskDirectoryDeletion {
    fn platform_default() -> Self {
        Self { direct: false }
    }

    fn direct() -> Self {
        Self { direct: true }
    }

    fn delete_task_directory(self, path: &Utf8Path) -> Result<()> {
        if self.direct {
            return remove_task_directory_direct(path);
        }
        remove_task_directory_platform(path)
    }
}

#[cfg(target_os = "macos")]
fn remove_task_directory_platform(path: &Utf8Path) -> Result<()> {
    trash::delete(path.as_std_path())
        .map_err(|source| Error::Message(format!("failed to move {} to trash: {source}", path)))
}

#[cfg(not(target_os = "macos"))]
fn remove_task_directory_platform(path: &Utf8Path) -> Result<()> {
    remove_task_directory_direct(path)
}

fn remove_task_directory_direct(path: &Utf8Path) -> Result<()> {
    fs_err::remove_dir_all(path).map_err(|source| Error::Io {
        path: path.to_path_buf().into_std_path_buf(),
        source,
    })
}

#[cfg(test)]
mod tests {
    use super::TaskDirectoryDeletion;
    use tempfile::tempdir;

    #[test]
    fn direct_task_directory_deletion_removes_directory() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let task_path = camino::Utf8PathBuf::from_path_buf(temp.path().join("task"))
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()));
        fs_err::create_dir_all(task_path.join("repo"))
            .unwrap_or_else(|error| panic!("failed to create {task_path}: {error}"));

        TaskDirectoryDeletion::direct()
            .delete_task_directory(&task_path)
            .unwrap_or_else(|error| panic!("failed to delete task directory: {error}"));

        assert!(!task_path.exists());
    }
}
