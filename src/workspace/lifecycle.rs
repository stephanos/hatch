use crate::{Error, Result};

use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone)]
pub(crate) struct WorkspaceLifecycleService {
    core: WorkspaceServiceCore,
}

impl WorkspaceLifecycleService {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn create_workspace(&self, force: bool) -> Result<()> {
        let paths = self.core.paths()?;
        fs_err::create_dir_all(&paths.workspace_root).map_err(|source| Error::Io {
            path: paths.workspace_root.clone().into_std_path_buf(),
            source,
        })?;
        let workspace_exists = paths.hatch_root.exists();
        if workspace_exists && !force {
            return Err(Error::Message(format!(
                "workspace already exists at {} - pass --force to re-create it at location",
                paths.workspace_root
            )));
        }
        if force && workspace_exists {
            fs_err::remove_dir_all(&paths.hatch_root).map_err(|source| Error::Io {
                path: paths.hatch_root.clone().into_std_path_buf(),
                source,
            })?;
        }
        self.core.store.ensure_workspace_files(&paths)?;
        self.core.store.save_workspace_root(&paths.workspace_root)?;
        let agents = paths.workspace_root.join("AGENTS.md");
        if !agents.exists() {
            fs_err::write(&agents, "## Workspace Instructions\n").map_err(|source| Error::Io {
                path: agents.clone().into_std_path_buf(),
                source,
            })?;
        }
        Ok(())
    }
}
