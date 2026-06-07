use camino::Utf8PathBuf;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppPaths {
    pub workspace_root: Utf8PathBuf,
    pub hatch_root: Utf8PathBuf,
    pub hooks_directory: Utf8PathBuf,
    pub state_directory: Utf8PathBuf,
    pub cache_directory: Utf8PathBuf,
    pub repos_directory: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectSummary {
    pub id: String,
    pub name: String,
    pub path: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskSummary {
    pub id: String,
    pub project: String,
    pub task: String,
    pub path: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct TaskRepoSummary {
    pub name: String,
    pub path: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupCandidate {
    pub project: String,
    pub task: String,
    pub path: Utf8PathBuf,
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ProjectCreationPlan {
    pub project: String,
    pub project_directory: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TaskCreationPlan {
    pub project: String,
    pub task: String,
    pub task_directory: Utf8PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectCreateRequest {
    pub name: String,
    #[serde(default)]
    pub force: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskCreateRequest {
    pub project: String,
    pub task: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddRepoRequest {
    pub repo: String,
    pub task_path: Utf8PathBuf,
    #[serde(default)]
    pub checkout_dir: Option<String>,
    #[serde(default)]
    pub force: bool,
    #[serde(default)]
    pub base_branch: Option<String>,
}
