use crate::AppPaths;
use crate::error::{IoResultExt, Result};

#[derive(Debug, Clone, Default)]
pub(crate) struct WorkspaceSetup;

impl WorkspaceSetup {
    pub(crate) fn new() -> Self {
        Self
    }

    pub(crate) fn ensure_workspace_paths(&self, paths: &AppPaths) -> Result<()> {
        fs_err::create_dir_all(&paths.hatch_root).at_path(&paths.hatch_root)?;
        fs_err::create_dir_all(&paths.state_directory).at_path(&paths.state_directory)?;
        fs_err::create_dir_all(&paths.cache_directory).at_path(&paths.cache_directory)?;
        fs_err::create_dir_all(&paths.repos_directory).at_path(&paths.repos_directory)?;
        Ok(())
    }
}
