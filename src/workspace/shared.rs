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
    retry_trash_when_finder_busy(|| trash::delete(path.as_std_path()), std::thread::sleep)
        .map_err(|source| Error::Message(format!("failed to move {} to trash: {source}", path)))
}

#[cfg(any(target_os = "macos", test))]
fn retry_trash_when_finder_busy(
    mut delete: impl FnMut() -> std::result::Result<(), trash::Error>,
    mut wait: impl FnMut(std::time::Duration),
) -> std::result::Result<(), trash::Error> {
    let mut result = delete();
    for delay_ms in [250, 500, 1000] {
        if !matches!(&result, Err(trash::Error::Os { description, .. }) if description.contains("(-15260)"))
        {
            return result;
        }
        wait(std::time::Duration::from_millis(delay_ms));
        result = delete();
    }
    result
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

    fn finder_busy() -> trash::Error {
        trash::Error::Os {
            code: 1,
            description: "The AppleScript exited with error. stderr: Finder got an error: The Finder is busy. (-15260)".to_string(),
        }
    }

    #[test]
    fn retries_busy_finder_until_trash_succeeds() {
        let mut attempts = 0;
        let mut waits = Vec::new();
        let result = super::retry_trash_when_finder_busy(
            || {
                attempts += 1;
                if attempts < 3 {
                    Err(finder_busy())
                } else {
                    Ok(())
                }
            },
            |delay| waits.push(delay.as_millis()),
        );

        assert!(result.is_ok());
        assert_eq!(attempts, 3);
        assert_eq!(waits, vec![250, 500]);
    }

    #[test]
    fn stops_retrying_persistently_busy_finder() {
        let mut attempts = 0;
        let mut waits = Vec::new();
        let result = super::retry_trash_when_finder_busy(
            || {
                attempts += 1;
                Err(finder_busy())
            },
            |delay| waits.push(delay.as_millis()),
        );

        assert!(result.unwrap_err().to_string().contains("(-15260)"));
        assert_eq!(attempts, 4);
        assert_eq!(waits, vec![250, 500, 1000]);
    }

    #[test]
    fn does_not_retry_other_trash_errors() {
        let mut attempts = 0;
        let mut waits = Vec::new();
        let result = super::retry_trash_when_finder_busy(
            || {
                attempts += 1;
                Err(trash::Error::Os {
                    code: 1,
                    description: "Not authorized (-1743)".to_string(),
                })
            },
            |delay| waits.push(delay.as_millis()),
        );

        assert!(result.unwrap_err().to_string().contains("(-1743)"));
        assert_eq!(attempts, 1);
        assert!(waits.is_empty());
    }

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
