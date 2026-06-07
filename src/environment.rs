use crate::AppPaths;
use crate::error::{Error, Result};
use camino::Utf8PathBuf;
use directories::BaseDirs;
use serde::{Deserialize, Serialize};
use std::env;

mod hooks;
mod setup;
mod state;

const HATCH_DIRECTORY_NAME: &str = ".hatch";
const HOOKS_DIRECTORY_NAME: &str = "hooks";
const STATE_DIRECTORY_NAME: &str = "state";
const CACHE_DIRECTORY_NAME: &str = "cache";
const REPOS_DIRECTORY_NAME: &str = "repos";
pub(crate) const PROJECT_MARKER_DIRECTORY: &str = ".hatch";

#[derive(Debug, Deserialize, Serialize)]
struct HatchConfig {
    workspace_root: Utf8PathBuf,
}

#[derive(Debug, Clone)]
pub struct HatchEnvironment {
    workspace_root_override: Option<Utf8PathBuf>,
    persist_workspace_root: bool,
    use_test_adapters: bool,
}

impl HatchEnvironment {
    pub fn from_env() -> Result<Self> {
        let workspace_root_override = env_path("HATCH_TEST_WORKSPACE_ROOT")?;
        let use_test_adapters = workspace_root_override.is_some();

        Ok(Self {
            workspace_root_override,
            persist_workspace_root: false,
            use_test_adapters,
        })
    }

    pub fn new(workspace_root_override: Option<Utf8PathBuf>) -> Self {
        let use_test_adapters = workspace_root_override.is_some();
        Self {
            workspace_root_override,
            persist_workspace_root: false,
            use_test_adapters,
        }
    }

    pub fn for_workspace_init(workspace_root: Utf8PathBuf) -> Self {
        Self {
            workspace_root_override: Some(workspace_root),
            persist_workspace_root: true,
            use_test_adapters: false,
        }
    }
}

#[derive(Debug, Clone)]
pub struct HatchStore {
    environment: HatchEnvironment,
}

impl HatchStore {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            environment: HatchEnvironment::from_env()?,
        })
    }

    pub fn new(environment: HatchEnvironment) -> Self {
        Self { environment }
    }

    pub fn paths(&self) -> Result<AppPaths> {
        let workspace_root = if let Some(workspace_root) = &self.environment.workspace_root_override
        {
            workspace_root.clone()
        } else if let Some(config) = read_config()? {
            config.workspace_root
        } else {
            let current_dir = Utf8PathBuf::from_path_buf(
                env::current_dir()
                    .map_err(|source| Error::Message(format!("failed to read cwd: {source}")))?,
            )
            .map_err(|path| {
                Error::Message(format!("cwd is not valid UTF-8: {}", path.display()))
            })?;
            discover_workspace_root(&current_dir).unwrap_or(current_dir)
        };

        let paths = self.app_paths_for_workspace_root(workspace_root);
        hooks::HookInstaller::new().sync_workspace_hooks(&paths.hooks_directory)?;
        Ok(paths)
    }

    pub(crate) fn ensure_workspace_files(&self, paths: &AppPaths) -> Result<()> {
        setup::WorkspaceSetup::new().ensure_workspace_paths(paths)?;
        hooks::HookInstaller::new().ensure_workspace_hooks(&paths.hooks_directory)
    }

    pub(crate) fn save_workspace_root(&self, workspace_root: &camino::Utf8Path) -> Result<()> {
        if !self.environment.persist_workspace_root {
            return Ok(());
        }
        write_config(&HatchConfig {
            workspace_root: workspace_root.to_path_buf(),
        })
    }

    pub(crate) fn ensure_project_hook_files(
        &self,
        hooks_directory: &camino::Utf8Path,
    ) -> Result<()> {
        hooks::HookInstaller::new().ensure_project_hooks(hooks_directory)
    }

    pub(crate) fn load_recent_projects(&self, paths: &AppPaths) -> Result<Vec<String>> {
        state::StateStore::new().load_recent_projects(paths)
    }

    pub(crate) fn save_recent_projects(&self, paths: &AppPaths, projects: &[String]) -> Result<()> {
        state::StateStore::new().save_recent_projects(paths, projects)
    }

    pub(crate) fn use_direct_task_deletion(&self) -> bool {
        self.environment.use_test_adapters
    }

    fn app_paths_for_workspace_root(&self, workspace_root: Utf8PathBuf) -> AppPaths {
        let hatch_root = workspace_root.join(HATCH_DIRECTORY_NAME);
        AppPaths {
            workspace_root: workspace_root.clone(),
            hatch_root: hatch_root.clone(),
            hooks_directory: hatch_root.join(HOOKS_DIRECTORY_NAME),
            state_directory: hatch_root.join(STATE_DIRECTORY_NAME),
            cache_directory: hatch_root.join(CACHE_DIRECTORY_NAME),
            repos_directory: hatch_root.join(REPOS_DIRECTORY_NAME),
        }
    }
}

fn read_config() -> Result<Option<HatchConfig>> {
    let path = config_file_path()?;
    if !path.exists() {
        return Ok(None);
    }
    let data = fs_err::read_to_string(&path).map_err(|source| Error::Io {
        path: path.clone().into_std_path_buf(),
        source,
    })?;
    let config = toml::from_str(&data).map_err(|source| {
        Error::Message(format!("failed to read hatch config {path}: {source}"))
    })?;
    Ok(Some(config))
}

fn write_config(config: &HatchConfig) -> Result<()> {
    let path = config_file_path()?;
    if let Some(parent) = path.parent() {
        fs_err::create_dir_all(parent).map_err(|source| Error::Io {
            path: parent.to_path_buf().into_std_path_buf(),
            source,
        })?;
    }
    let data = toml::to_string_pretty(config)
        .map_err(|source| Error::Message(format!("failed to write hatch config: {source}")))?;
    fs_err::write(&path, data).map_err(|source| Error::Io {
        path: path.into_std_path_buf(),
        source,
    })
}

fn config_file_path() -> Result<Utf8PathBuf> {
    if let Some(path) = env_path("HATCH_CONFIG_FILE")? {
        return Ok(path);
    }
    let base = BaseDirs::new()
        .ok_or_else(|| Error::Message("failed to locate OS config directory".to_string()))?;
    Utf8PathBuf::from_path_buf(base.config_dir().join("hatch").join("config.toml")).map_err(
        |path| {
            Error::Message(format!(
                "config path is not valid UTF-8: {}",
                path.display()
            ))
        },
    )
}

fn discover_workspace_root(start: &camino::Utf8Path) -> Option<Utf8PathBuf> {
    start
        .ancestors()
        .find(|path| path.join(".hatch/lib/hatch.sh").is_file())
        .map(camino::Utf8Path::to_path_buf)
}

fn env_path(key: &str) -> Result<Option<Utf8PathBuf>> {
    let Ok(value) = env::var(key) else {
        return Ok(None);
    };
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    expand_tilde(trimmed, &home_dir()?).map(Some)
}

fn home_dir() -> Result<Utf8PathBuf> {
    let home = env::var("HOME").map_err(|_| Error::Message("HOME is not set".to_string()))?;
    Utf8PathBuf::from_path_buf(home.into())
        .map_err(|path| Error::Message(format!("HOME is not valid UTF-8: {}", path.display())))
}

fn expand_tilde(value: &str, home: &camino::Utf8Path) -> Result<Utf8PathBuf> {
    if value == "~" {
        return Ok(home.to_path_buf());
    }
    if let Some(rest) = value.strip_prefix("~/") {
        return Ok(home.join(rest));
    }
    Utf8PathBuf::from_path_buf(value.into())
        .map_err(|path| Error::Message(format!("path is not valid UTF-8: {}", path.display())))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn utf8_path(path: &std::path::Path) -> Utf8PathBuf {
        Utf8PathBuf::from_path_buf(path.to_path_buf())
            .unwrap_or_else(|path| panic!("path is not valid UTF-8: {}", path.display()))
    }

    fn test_paths(root: &camino::Utf8Path) -> AppPaths {
        let workspace_root = root.join("Workspace");
        let hatch_root = workspace_root.join(HATCH_DIRECTORY_NAME);
        AppPaths {
            workspace_root: workspace_root.clone(),
            hatch_root: hatch_root.clone(),
            hooks_directory: hatch_root.join(HOOKS_DIRECTORY_NAME),
            state_directory: hatch_root.join(STATE_DIRECTORY_NAME),
            cache_directory: hatch_root.join(CACHE_DIRECTORY_NAME),
            repos_directory: hatch_root.join(REPOS_DIRECTORY_NAME),
        }
    }

    #[test]
    fn workspace_root_discovery_uses_initialized_workspace_above_project() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let workspace_root = root.join("Workspace");
        let task_path = workspace_root.join("api/setup-ci");
        fs_err::create_dir_all(workspace_root.join(".hatch/lib"))
            .unwrap_or_else(|error| panic!("failed to create workspace hatch lib: {error}"));
        fs_err::write(workspace_root.join(".hatch/lib/hatch.sh"), "")
            .unwrap_or_else(|error| panic!("failed to write hatch.sh: {error}"));
        fs_err::create_dir_all(workspace_root.join("api/.hatch/hooks"))
            .unwrap_or_else(|error| panic!("failed to create project hatch dir: {error}"));
        fs_err::create_dir_all(&task_path)
            .unwrap_or_else(|error| panic!("failed to create task path: {error}"));

        assert_eq!(discover_workspace_root(&task_path), Some(workspace_root));
    }

    #[test]
    fn hook_installer_creates_missing_project_hooks_without_overwriting_existing_files() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let hooks_directory = root.join("hooks");
        fs_err::create_dir_all(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to create {hooks_directory}: {error}"));
        let existing = hooks_directory.join("task_open.sh");
        fs_err::write(&existing, "#!/usr/bin/env sh\nprintf 'custom\\n'\n")
            .unwrap_or_else(|error| panic!("failed to write {existing}: {error}"));

        super::hooks::HookInstaller::new()
            .ensure_project_hooks(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to scaffold project hooks: {error}"));

        assert_eq!(
            fs_err::read_to_string(&existing)
                .unwrap_or_else(|error| panic!("failed to read {existing}: {error}")),
            "#!/usr/bin/env sh\nprintf 'custom\\n'\n"
        );
        assert!(hooks_directory.join("project_new.sh").exists());
        assert!(hooks_directory.join("repo_delete.sh").exists());
    }

    #[test]
    fn hook_installer_writes_workspace_default_hook_copies() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let hooks_directory = root.join("hooks");

        super::hooks::HookInstaller::new()
            .ensure_workspace_hooks(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to scaffold workspace hooks: {error}"));

        let default_hook = hooks_directory.join("task_open.default.sh");
        let data = fs_err::read_to_string(&default_hook)
            .unwrap_or_else(|error| panic!("failed to read {default_hook}: {error}"));
        assert!(data.starts_with("# This is Hatch's bundled default hook for task_open.\n"));
        assert!(data.ends_with(include_str!("../templates/hooks/task_open.sh")));
    }

    #[test]
    fn hook_installer_refreshes_workspace_hook_lib_files() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let hooks_directory = root.join("hooks");
        let lib_directory = root.join("lib");
        fs_err::create_dir_all(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to create {hooks_directory}: {error}"));
        fs_err::create_dir_all(&lib_directory)
            .unwrap_or_else(|error| panic!("failed to create {lib_directory}: {error}"));
        let repo_lib = lib_directory.join("repo.sh");
        fs_err::write(&repo_lib, "old internal repo lib\n")
            .unwrap_or_else(|error| panic!("failed to write {repo_lib}: {error}"));

        super::hooks::HookInstaller::new()
            .sync_workspace_hooks(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to sync workspace hooks: {error}"));

        let data = fs_err::read_to_string(&repo_lib)
            .unwrap_or_else(|error| panic!("failed to read {repo_lib}: {error}"));
        assert_eq!(data, include_str!("../templates/lib/repo.sh"));
    }

    #[test]
    fn hook_installer_upgrades_workspace_hook_that_still_matches_previous_default() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let hooks_directory = root.join("hooks");
        fs_err::create_dir_all(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to create {hooks_directory}: {error}"));
        let old_default = "# This is Hatch's bundled default hook for task_open.\n# Hatch rewrites this file when its bundled defaults change.\n# Edit task_open.sh to customize behavior; Hatch only upgrades it while it still matches a previous default.\n\n#!/usr/bin/env sh\nprintf 'old default\\n'\n";
        fs_err::write(hooks_directory.join("task_open.default.sh"), old_default)
            .unwrap_or_else(|error| panic!("failed to write old default hook: {error}"));
        fs_err::write(
            hooks_directory.join("task_open.sh"),
            "#!/usr/bin/env sh\nprintf 'old default\\n'\n",
        )
        .unwrap_or_else(|error| panic!("failed to write old user hook: {error}"));

        super::hooks::HookInstaller::new()
            .ensure_workspace_hooks(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to scaffold workspace hooks: {error}"));

        let hook = fs_err::read_to_string(hooks_directory.join("task_open.sh"))
            .unwrap_or_else(|error| panic!("failed to read upgraded hook: {error}"));
        assert_eq!(hook, include_str!("../templates/hooks/task_open.sh"));
    }

    #[test]
    fn hook_installer_preserves_workspace_hook_that_differs_from_previous_default() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let hooks_directory = root.join("hooks");
        fs_err::create_dir_all(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to create {hooks_directory}: {error}"));
        let old_default = "# This is Hatch's bundled default hook for task_open.\n# Hatch rewrites this file when its bundled defaults change.\n# Edit task_open.sh to customize behavior; Hatch only upgrades it while it still matches a previous default.\n\n#!/usr/bin/env sh\nprintf 'old default\\n'\n";
        fs_err::write(hooks_directory.join("task_open.default.sh"), old_default)
            .unwrap_or_else(|error| panic!("failed to write old default hook: {error}"));
        fs_err::write(
            hooks_directory.join("task_open.sh"),
            "#!/usr/bin/env sh\nprintf 'custom\\n'\n",
        )
        .unwrap_or_else(|error| panic!("failed to write custom user hook: {error}"));

        super::hooks::HookInstaller::new()
            .ensure_workspace_hooks(&hooks_directory)
            .unwrap_or_else(|error| panic!("failed to scaffold workspace hooks: {error}"));

        let hook = fs_err::read_to_string(hooks_directory.join("task_open.sh"))
            .unwrap_or_else(|error| panic!("failed to read preserved hook: {error}"));
        assert_eq!(hook, "#!/usr/bin/env sh\nprintf 'custom\\n'\n");
    }

    #[test]
    fn workspace_setup_creates_workspace_directories() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let paths = test_paths(&root);

        super::setup::WorkspaceSetup::new()
            .ensure_workspace_paths(&paths)
            .unwrap_or_else(|error| panic!("failed to create workspace directories: {error}"));

        assert!(paths.hatch_root.is_dir());
        assert!(paths.state_directory.is_dir());
        assert!(paths.cache_directory.is_dir());
        assert!(paths.repos_directory.is_dir());
    }

    #[test]
    fn state_store_round_trips_recent_projects() {
        let root = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = utf8_path(root.path());
        let paths = test_paths(&root);
        let state = super::state::StateStore::new();

        state
            .save_recent_projects(&paths, &["api".to_string(), "web".to_string()])
            .unwrap_or_else(|error| panic!("failed to save recent projects: {error}"));
        assert_eq!(
            state
                .load_recent_projects(&paths)
                .unwrap_or_else(|error| panic!("failed to load recent projects: {error}")),
            vec!["api".to_string(), "web".to_string()]
        );

        state
            .save_recent_projects(&paths, &[])
            .unwrap_or_else(|error| panic!("failed to clear recent projects: {error}"));
        assert_eq!(
            state
                .load_recent_projects(&paths)
                .unwrap_or_else(|error| panic!("failed to load cleared recent projects: {error}")),
            Vec::<String>::new()
        );
    }
}
