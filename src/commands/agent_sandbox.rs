use anyhow::Context;
use nono::{AccessMode, CapabilitySet};
use std::env;
use std::path::{Path, PathBuf};

use super::agent_profile::ProfileContext;
use super::agent_profile::policy::{ProfilePathKind, profile_policy};

mod path_admission;
use path_admission::PathAdmission;

#[derive(Debug)]
pub(crate) struct AgentSandboxConfig<'a> {
    pub(crate) profile: &'a [String],
    pub(crate) profile_cache: Option<&'a Path>,
    pub(crate) registry: Option<&'a str>,
    pub(crate) allow: &'a [PathBuf],
    pub(crate) read: &'a [PathBuf],
    pub(crate) write: &'a [PathBuf],
    pub(crate) block_net: bool,
    pub(crate) allow_port: &'a [u16],
}

pub(crate) fn build_capabilities(
    config: &AgentSandboxConfig<'_>,
    program: &Path,
) -> anyhow::Result<CapabilitySet> {
    let workdir = env::current_dir().context("failed to read cwd")?;
    build_capabilities_with_context(config, program, &workdir)
}

pub(crate) fn build_capabilities_with_context(
    config: &AgentSandboxConfig<'_>,
    program: &Path,
    workdir: &Path,
) -> anyhow::Result<CapabilitySet> {
    let plan = SandboxPlan::build(config, program, workdir)?;
    let mut caps = CapabilitySet::new();
    for admission in plan.paths {
        caps = admission.apply(caps)?;
    }
    if plan.block_network {
        caps = caps.block_network();
    }
    for port in plan.allow_ports {
        caps = caps.allow_localhost_port(port);
    }
    Ok(caps)
}

struct SandboxPlan {
    paths: Vec<PathAdmission>,
    block_network: bool,
    allow_ports: Vec<u16>,
}

impl SandboxPlan {
    fn build(
        config: &AgentSandboxConfig<'_>,
        program: &Path,
        workdir: &Path,
    ) -> anyhow::Result<Self> {
        let mut paths = Vec::new();
        paths.extend(baseline_read_paths());
        paths.push(PathAdmission::required(program, AccessMode::Read));
        paths.extend(program_support_paths(program));
        let profile_context = profile_context(workdir)?;
        let cache_dir = profile_cache_dir(config)?;
        let registry_url = match config.registry {
            Some(value) => value,
            None => super::agent_profile::default_registry_url(),
        };
        let mut block_network = config.block_net;
        for profile in config.profile {
            let profile = super::agent_profile::load_profile(profile, &cache_dir, registry_url)?;
            let policy = profile_policy(&profile, &profile_context)?;
            paths.extend(profile_policy_paths(policy.paths));
            block_network |= policy.block_network;
        }
        for path in config.allow {
            paths.push(PathAdmission::required(path, AccessMode::ReadWrite));
        }
        for path in config.read {
            paths.push(PathAdmission::required(path, AccessMode::Read));
        }
        for path in config.write {
            paths.push(PathAdmission::required(path, AccessMode::Write));
        }
        Ok(Self {
            paths,
            block_network,
            allow_ports: config.allow_port.to_vec(),
        })
    }
}

fn profile_policy_paths(
    paths: Vec<super::agent_profile::policy::ProfilePath>,
) -> Vec<PathAdmission> {
    paths
        .into_iter()
        .map(|path| match path.kind {
            ProfilePathKind::Path => PathAdmission::optional_path(path.path, path.mode),
            ProfilePathKind::File => PathAdmission::optional_file(path.path, path.mode),
        })
        .collect()
}

fn baseline_read_paths() -> Vec<PathAdmission> {
    [
        "/bin", "/etc", "/lib", "/lib64", "/opt", "/sbin", "/System", "/Library", "/usr",
    ]
    .into_iter()
    .map(Path::new)
    .filter(|path| path.is_dir())
    .map(|path| PathAdmission::optional_path(path, AccessMode::Read))
    .collect()
}

fn program_support_paths(program: &Path) -> Vec<PathAdmission> {
    let components = program.components().collect::<Vec<_>>();
    let Some(index) = components
        .iter()
        .position(|component| component.as_os_str() == "node_modules")
    else {
        return Vec::new();
    };
    let mut node_modules = PathBuf::new();
    for component in &components[..=index] {
        node_modules.push(component.as_os_str());
    }
    if node_modules.is_dir() {
        vec![PathAdmission::optional_path(node_modules, AccessMode::Read)]
    } else {
        Vec::new()
    }
}

fn profile_context(workdir: &Path) -> anyhow::Result<ProfileContext> {
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| anyhow::anyhow!("HOME is not set"))?;
    Ok(ProfileContext {
        home,
        workdir: workdir.to_path_buf(),
    })
}

fn profile_cache_dir(config: &AgentSandboxConfig<'_>) -> anyhow::Result<PathBuf> {
    if let Some(path) = config.profile_cache {
        return Ok(path.to_path_buf());
    }
    if let Some(path) = env::var_os("HATCH_NONO_CACHE_DIR") {
        return Ok(PathBuf::from(path));
    }
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| anyhow::anyhow!("HOME is not set"))?;
    Ok(home.join(".cache/hatch/nono"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_capabilities_for_allowed_scope_without_applying_sandbox() {
        let temp =
            tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let program = temp.path().join("agent");
        fs_err::write(&program, "#!/bin/sh\n")
            .unwrap_or_else(|error| panic!("failed to write fake agent: {error}"));
        let config = AgentSandboxConfig {
            profile: &[],
            profile_cache: None,
            registry: None,
            allow: &[temp.path().to_path_buf()],
            read: &[],
            write: &[],
            block_net: true,
            allow_port: &[3000],
        };

        let caps = build_capabilities(&config, &program)
            .unwrap_or_else(|error| panic!("failed to build capabilities: {error}"));

        let scope = fs_err::canonicalize(temp.path())
            .unwrap_or_else(|error| panic!("failed to canonicalize tempdir: {error}"));
        assert!(caps.path_covered(&scope));
    }

    #[test]
    fn builds_capabilities_from_cached_registry_profile() {
        let temp =
            tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = temp.path();
        let cache = root.join("cache");
        let home = root.join("home");
        let workdir = root.join("workspace");
        let profile_dir = cache.join("packages/always-further/codex/profiles");
        fs_err::create_dir_all(&profile_dir)
            .unwrap_or_else(|error| panic!("failed to create profile cache: {error}"));
        fs_err::create_dir_all(home.join(".codex"))
            .unwrap_or_else(|error| panic!("failed to create home config: {error}"));
        fs_err::create_dir_all(workdir.join("docs"))
            .unwrap_or_else(|error| panic!("failed to create workdir docs: {error}"));
        fs_err::write(
            cache.join("packages/always-further/codex/package.json"),
            r#"{
  "schema_version": 1,
  "name": "codex",
  "artifacts": [{"type": "profile", "path": "policy.json", "install_as": "codex"}]
}"#,
        )
        .unwrap_or_else(|error| panic!("failed to write cached package manifest: {error}"));
        fs_err::write(
            cache.join("packages/always-further/codex/.hatch-refreshed-at"),
            format!(
                "{}\n",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_else(|error| panic!("system clock is before UNIX epoch: {error}"))
                    .as_secs()
            ),
        )
        .unwrap_or_else(|error| panic!("failed to write cached package refresh marker: {error}"));
        fs_err::write(
            profile_dir.join("codex.json"),
            format!(
                r#"{{
  "filesystem": {{
    "allow": ["{}/.codex"],
    "read": ["$WORKDIR/docs"]
  }},
  "workdir": {{ "access": "readwrite" }},
  "network": {{ "block": true }}
}}"#,
                home.display()
            ),
        )
        .unwrap_or_else(|error| panic!("failed to write cached profile: {error}"));
        let program = root.join("agent");
        fs_err::write(&program, "#!/bin/sh\n")
            .unwrap_or_else(|error| panic!("failed to write fake agent: {error}"));
        let profiles = vec!["always-further/codex".to_string()];
        let config = AgentSandboxConfig {
            profile: &profiles,
            profile_cache: Some(&cache),
            registry: None,
            allow: &[],
            read: &[],
            write: &[],
            block_net: false,
            allow_port: &[],
        };

        let caps = build_capabilities_with_context(&config, &program, &workdir)
            .unwrap_or_else(|error| panic!("failed to build capabilities: {error}"));

        let home_codex = fs_err::canonicalize(home.join(".codex"))
            .unwrap_or_else(|error| panic!("failed to canonicalize home codex: {error}"));
        let workdir = fs_err::canonicalize(workdir)
            .unwrap_or_else(|error| panic!("failed to canonicalize workdir: {error}"));
        let docs = fs_err::canonicalize(workdir.join("docs"))
            .unwrap_or_else(|error| panic!("failed to canonicalize docs: {error}"));
        assert!(caps.path_covered(&home_codex));
        assert!(caps.path_covered(&workdir));
        assert!(caps.path_covered(&docs));
    }
}
