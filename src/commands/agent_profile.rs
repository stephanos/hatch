use anyhow::Context;
use nono::AccessMode;
use serde::Deserialize;
use std::path::{Path, PathBuf};

const DEFAULT_REGISTRY_URL: &str = "https://registry.nono.sh";

mod cache;
pub(crate) mod policy;

#[derive(Debug, Clone)]
pub(crate) struct ProfileContext {
    pub(crate) home: PathBuf,
    pub(crate) workdir: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct AgentProfile {
    #[serde(default)]
    pub(crate) groups: ProfileGroups,
    #[serde(default)]
    pub(crate) filesystem: ProfileFilesystem,
    #[serde(default)]
    pub(crate) network: ProfileNetwork,
    #[serde(default)]
    pub(crate) workdir: ProfileWorkdir,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub(crate) struct ProfileGroups {
    #[serde(default)]
    pub(crate) include: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub(crate) struct ProfileFilesystem {
    #[serde(default)]
    pub(crate) allow: Vec<String>,
    #[serde(default)]
    pub(crate) read: Vec<String>,
    #[serde(default)]
    pub(crate) write: Vec<String>,
    #[serde(default)]
    pub(crate) allow_file: Vec<String>,
    #[serde(default)]
    pub(crate) read_file: Vec<String>,
    #[serde(default)]
    pub(crate) write_file: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub(crate) struct ProfileNetwork {
    #[serde(default)]
    pub(crate) block: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub(crate) struct ProfileWorkdir {
    #[serde(default)]
    pub(crate) access: Option<String>,
}

pub(crate) fn default_registry_url() -> &'static str {
    DEFAULT_REGISTRY_URL
}

pub(crate) fn load_profile(
    profile: &str,
    cache_dir: &Path,
    registry_url: &str,
) -> anyhow::Result<AgentProfile> {
    if is_file_path_ref(profile) {
        return load_profile_path(Path::new(profile));
    }
    cache::load_registry_profile(profile, cache_dir, registry_url)
}

pub(crate) fn expand_path(value: &str, context: &ProfileContext) -> PathBuf {
    let expanded = if value == "~" || value == "$HOME" {
        context.home.to_string_lossy().to_string()
    } else if let Some(rest) = value.strip_prefix("~/") {
        format!("{}/{rest}", context.home.display())
    } else if let Some(rest) = value.strip_prefix("$HOME/") {
        format!("{}/{rest}", context.home.display())
    } else if value == "$WORKDIR" {
        context.workdir.to_string_lossy().to_string()
    } else if let Some(rest) = value.strip_prefix("$WORKDIR/") {
        format!("{}/{rest}", context.workdir.display())
    } else if value == "$TMPDIR" {
        std::env::temp_dir().to_string_lossy().to_string()
    } else if let Some(rest) = value.strip_prefix("$TMPDIR/") {
        format!("{}/{rest}", std::env::temp_dir().display())
    } else {
        value.to_string()
    };
    PathBuf::from(expanded)
}

pub(crate) fn known_group_paths(name: &str) -> Option<Vec<(&'static str, AccessMode)>> {
    match name {
        "codex_macos" => Some(vec![
            (
                "$HOME/Library/Keychains/login.keychain-db",
                AccessMode::ReadWrite,
            ),
            (
                "$HOME/Library/Keychains/metadata.keychain-db",
                AccessMode::ReadWrite,
            ),
        ]),
        "git_config" => Some(vec![
            ("$HOME/.gitconfig", AccessMode::Read),
            ("$HOME/.gitignore_global", AccessMode::Read),
            ("$HOME/.config/git/config", AccessMode::Read),
            ("$HOME/.config/git/ignore", AccessMode::Read),
            ("$HOME/.config/git/attributes", AccessMode::Read),
        ]),
        "linux_sysfs_read" => Some(vec![("/sys", AccessMode::Read)]),
        "nix_runtime" => Some(vec![
            ("~/.nix-profile", AccessMode::Read),
            ("~/.local/state/nix/profile", AccessMode::Read),
            ("~/.local/state/nix/profiles", AccessMode::Read),
            ("~/.nix-defexpr", AccessMode::Read),
            ("~/.local/state/nix/defexpr", AccessMode::Read),
            ("/run/current-system/sw", AccessMode::Read),
            ("/etc/profiles/per-user", AccessMode::Read),
            ("/nix/var/nix/profiles", AccessMode::Read),
            ("/nix/store", AccessMode::Read),
        ]),
        "node_runtime" => Some(vec![
            ("~/.nvm", AccessMode::Read),
            ("~/.fnm", AccessMode::Read),
            ("~/.npm", AccessMode::Read),
            ("~/.node", AccessMode::Read),
            ("~/.local/share/fnm", AccessMode::Read),
            ("~/.local/share/mise", AccessMode::Read),
            ("/usr/local/lib/node_modules", AccessMode::Read),
            ("~/Library/pnpm", AccessMode::Read),
            ("~/.local/share/pnpm", AccessMode::Read),
        ]),
        "python_runtime" => Some(vec![
            ("~/.pyenv", AccessMode::Read),
            ("~/.local/lib", AccessMode::Read),
            ("~/.local/share/uv", AccessMode::Read),
            ("~/.conda", AccessMode::Read),
        ]),
        "rust_runtime" => Some(vec![
            ("~/.cargo", AccessMode::Read),
            ("~/.rustup", AccessMode::Read),
        ]),
        "user_caches_macos" => Some(vec![
            ("~/Library/Caches", AccessMode::ReadWrite),
            ("~/Library/Logs", AccessMode::ReadWrite),
            ("~/Library/Preferences", AccessMode::Read),
        ]),
        "unlink_protection" => Some(Vec::new()),
        _ => None,
    }
}

fn load_profile_path(path: &Path) -> anyhow::Result<AgentProfile> {
    let data = fs_err::read_to_string(path)
        .with_context(|| format!("failed to read profile {}", path.display()))?;
    serde_json::from_str(&data)
        .with_context(|| format!("failed to parse profile {}", path.display()))
}

fn is_file_path_ref(value: &str) -> bool {
    value.starts_with('/') || value.starts_with('.') || value.ends_with(".json")
}
