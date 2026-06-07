use crate::matching::{format_ambiguous_query, fuzzy_score};
use crate::workspace::helpers::{ensure_path_absent, validate_identifier};
use crate::{AppPaths, Error, Result, TaskCreationPlan, TaskSummary};

use super::query::{QueryResolution, resolve_query};
use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone)]
pub(crate) struct TaskService {
    core: WorkspaceServiceCore,
}

impl TaskService {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn list_tasks(&self, paths: &AppPaths) -> Result<Vec<crate::TaskSummary>> {
        self.core.discovery.list_tasks(paths)
    }

    pub(crate) fn plan_task_creation(
        &self,
        paths: &AppPaths,
        project: &str,
        task: &str,
    ) -> Result<TaskCreationPlan> {
        let task = validate_identifier("task name", task)?;
        let project_path = self.core.project_path(paths, project);
        self.core.ensure_project_exists(&project_path)?;
        let task_directory = self.core.task_path(paths, project, &task);
        ensure_path_absent(&task_directory)?;
        Ok(TaskCreationPlan {
            project: project.to_string(),
            task,
            task_directory,
        })
    }

    pub(crate) fn delete_task(&self, paths: &AppPaths, query: &str) -> Result<TaskSummary> {
        let task = self.resolve_task_query(paths, query)?;
        self.core.delete_task_directory(&task.path)?;
        Ok(task)
    }

    pub(crate) fn resolve_task_query(&self, paths: &AppPaths, query: &str) -> Result<TaskSummary> {
        let query = self.normalize_task_query(query)?;
        let tasks = self.list_tasks(paths)?;
        match resolve_task_query_resolution(query.as_str(), &tasks) {
            QueryResolution::Match(task) => Ok(task),
            QueryResolution::NotFound => Err(Error::Message(format!("no task matches: {query}"))),
            QueryResolution::Ambiguous(candidates) => Err(Error::Message(format_ambiguous_query(
                "task",
                &query,
                &candidates,
            ))),
        }
    }

    fn normalize_task_query(&self, query: &str) -> Result<String> {
        let query = query.trim();
        if query.is_empty() {
            return Err(Error::Message("task query cannot be empty".to_string()));
        }
        if let Some(pr_url) = parse_github_pull_request_url(query) {
            return self.resolve_task_query_from_pr_url(&pr_url);
        }
        Ok(query.to_string())
    }

    fn resolve_task_query_from_pr_url(&self, pr_url: &str) -> Result<String> {
        let head_ref = self.core.github.pull_request_head_ref(pr_url)?;
        branch_ref_tail(&head_ref)
            .map(ToString::to_string)
            .ok_or_else(|| Error::Message(format!("PR head branch has no task name: {pr_url}")))
    }
}

fn resolve_task_query_resolution(
    query: &str,
    tasks: &[TaskSummary],
) -> QueryResolution<TaskSummary> {
    let resolution = resolve_task_query_candidates(query, tasks);
    let resolution = match resolution {
        QueryResolution::NotFound => branch_tail_query(query)
            .map(|tail| resolve_task_query_candidates(tail, tasks))
            .unwrap_or(QueryResolution::NotFound),
        resolution => resolution,
    };
    match resolution {
        QueryResolution::Match(task) => QueryResolution::Match(task.clone()),
        QueryResolution::NotFound => QueryResolution::NotFound,
        QueryResolution::Ambiguous(candidates) => QueryResolution::Ambiguous(candidates),
    }
}

fn resolve_task_query_candidates<'a>(
    query: &str,
    tasks: &'a [TaskSummary],
) -> QueryResolution<&'a TaskSummary> {
    resolve_query(
        query,
        tasks.iter(),
        |task| [task.id.as_str(), task.task.as_str()],
        |task, query| fuzzy_score(&task.id, query),
        |task| task.id.as_str(),
        |task| task.id.clone(),
    )
}

fn branch_ref_tail(branch_ref: &str) -> Option<&str> {
    branch_ref
        .trim()
        .rsplit('/')
        .next()
        .filter(|segment| !segment.is_empty())
}

fn branch_tail_query(query: &str) -> Option<&str> {
    query
        .contains('/')
        .then(|| branch_ref_tail(query))
        .flatten()
}

fn parse_github_pull_request_url(query: &str) -> Option<String> {
    let mut url = url::Url::parse(query).ok()?;
    if url.scheme() != "https" || url.host_str()? != "github.com" {
        return None;
    }
    url.set_query(None);
    url.set_fragment(None);
    let parts = url
        .path_segments()?
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>();
    let [owner, repo, pull, number] = parts.as_slice() else {
        return None;
    };
    if owner.is_empty() || repo.is_empty() {
        return None;
    }
    if *pull != "pull" || number.parse::<u64>().is_err() {
        return None;
    }
    Some(url.to_string().trim_end_matches('/').to_string())
}

#[cfg(test)]
mod tests {
    use super::{QueryResolution, TaskSummary, branch_tail_query, resolve_task_query_resolution};
    use camino::Utf8PathBuf;

    #[test]
    fn branch_tail_query_uses_last_segment() {
        assert_eq!(
            branch_tail_query("stephanos/node-20-depre"),
            Some("node-20-depre")
        );
        assert_eq!(branch_tail_query("node-20-depre"), None);
        assert_eq!(branch_tail_query("stephanos/"), None);
    }

    #[test]
    fn resolves_exact_project_task_before_branch_tail_fallback() {
        let tasks = vec![
            task("stephanos", "node-20-depre"),
            task("test-crew", "node-20-depre"),
        ];

        assert_eq!(
            resolve_task_query_resolution("stephanos/node-20-depre", &tasks),
            QueryResolution::Match(task("stephanos", "node-20-depre"))
        );
    }

    fn task(project: &str, task: &str) -> TaskSummary {
        TaskSummary {
            id: format!("{project}/{task}"),
            project: project.to_string(),
            task: task.to_string(),
            path: Utf8PathBuf::from(format!("Workspace/{project}/{task}")),
        }
    }
}
