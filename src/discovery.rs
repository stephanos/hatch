use crate::error::{IoResultExt, Result};
use crate::{AppPaths, ProjectSummary, TaskRepoSummary, TaskSummary};
use camino::Utf8PathBuf;

#[derive(Debug, Default, Clone)]
pub struct WorkspaceDiscovery;

impl WorkspaceDiscovery {
    pub fn list_projects(&self, paths: &AppPaths) -> Result<Vec<ProjectSummary>> {
        if !paths.workspace_root.exists() {
            return Ok(Vec::new());
        }

        let mut projects = Vec::new();
        for entry in fs_err::read_dir(&paths.workspace_root).at_path(&paths.workspace_root)? {
            let entry = entry.at_path(&paths.workspace_root)?;
            let path = utf8_path(entry.path())?;
            let name = path.file_name().unwrap_or_default();
            if matches!(name, "old" | "skills" | ".hatch") {
                continue;
            }
            if path.is_dir()
                && path
                    .join(crate::environment::PROJECT_MARKER_DIRECTORY)
                    .exists()
            {
                projects.push(ProjectSummary {
                    id: name.to_string(),
                    name: name.to_string(),
                    path,
                });
            }
        }
        projects.sort_by(|left, right| left.name.cmp(&right.name));
        Ok(projects)
    }

    pub fn list_tasks(&self, paths: &AppPaths) -> Result<Vec<TaskSummary>> {
        let mut tasks = Vec::new();
        for project in self.list_projects(paths)? {
            for entry in fs_err::read_dir(&project.path).at_path(&project.path)? {
                let entry = entry.at_path(&project.path)?;
                let path = utf8_path(entry.path())?;
                let task = path.file_name().unwrap_or_default();
                if task == ".hatch" {
                    continue;
                }
                if !path.is_dir() {
                    continue;
                }
                tasks.push(TaskSummary {
                    id: format!("{}/{}", project.name, task),
                    project: project.name.clone(),
                    task: task.to_string(),
                    path,
                });
            }
        }
        tasks
            .sort_by(|left, right| (&left.project, &left.task).cmp(&(&right.project, &right.task)));
        Ok(tasks)
    }

    pub(crate) fn list_task_repos(
        &self,
        task_path: &camino::Utf8Path,
    ) -> Result<Vec<TaskRepoSummary>> {
        let mut repos = Vec::new();
        for entry in fs_err::read_dir(task_path).at_path(task_path)? {
            let entry = entry.at_path(task_path)?;
            let path = utf8_path(entry.path())?;
            if !path.is_dir() || !path.join(".git").exists() {
                continue;
            }
            let name = path.file_name().unwrap_or_default().to_string();
            repos.push(TaskRepoSummary { name, path });
        }
        repos.sort_by(|left, right| left.name.cmp(&right.name));
        Ok(repos)
    }
}

fn utf8_path(path: std::path::PathBuf) -> Result<Utf8PathBuf> {
    Utf8PathBuf::from_path_buf(path.clone())
        .map_err(|_| crate::Error::Message(format!("path is not valid UTF-8: {}", path.display())))
}
