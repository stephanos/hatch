use crate::error::{IoResultExt, Result};
use crate::{AppPaths, Error};

const RECENT_PROJECTS_FILENAME: &str = "recent-projects.json";

#[derive(Debug, Clone, Default)]
pub(crate) struct StateStore;

impl StateStore {
    pub(crate) fn new() -> Self {
        Self
    }

    pub(crate) fn load_recent_projects(&self, paths: &AppPaths) -> Result<Vec<String>> {
        let file = paths.state_directory.join(RECENT_PROJECTS_FILENAME);
        if !file.exists() {
            return Ok(Vec::new());
        }
        let data = fs_err::read_to_string(&file).at_path(&file)?;
        if data.trim().is_empty() {
            let _ = fs_err::remove_file(&file);
            return Ok(Vec::new());
        }
        serde_json::from_str(&data)
            .map_err(|source| Error::Message(format!("failed to parse JSON at {file}: {source}")))
    }

    pub(crate) fn save_recent_projects(&self, paths: &AppPaths, projects: &[String]) -> Result<()> {
        let file = paths.state_directory.join(RECENT_PROJECTS_FILENAME);
        if projects.is_empty() {
            let _ = fs_err::remove_file(file);
            return Ok(());
        }
        fs_err::create_dir_all(&paths.state_directory).at_path(&paths.state_directory)?;
        let data = serde_json::to_string_pretty(projects).map_err(|source| {
            Error::Message(format!("failed to encode recent projects: {source}"))
        })?;
        fs_err::write(&file, data).at_path(file)
    }
}
