use nono::AccessMode;
use std::path::PathBuf;

use super::{AgentProfile, ProfileContext};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ProfilePolicy {
    pub(crate) paths: Vec<ProfilePath>,
    pub(crate) block_network: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ProfilePath {
    pub(crate) path: PathBuf,
    pub(crate) mode: AccessMode,
    pub(crate) kind: ProfilePathKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ProfilePathKind {
    Path,
    File,
}

pub(crate) fn profile_policy(
    profile: &AgentProfile,
    context: &ProfileContext,
) -> anyhow::Result<ProfilePolicy> {
    let mut paths = Vec::new();
    for group in &profile.groups.include {
        if let Some(group_paths) = super::known_group_paths(group) {
            for (path, mode) in group_paths {
                paths.push(ProfilePath {
                    path: super::expand_path(path, context),
                    mode,
                    kind: ProfilePathKind::Path,
                });
            }
        }
    }
    if let Some(access) = &profile.workdir.access
        && let Some(mode) = workdir_access_mode(access)?
    {
        paths.push(ProfilePath {
            path: context.workdir.clone(),
            mode,
            kind: ProfilePathKind::Path,
        });
    }
    add_profile_paths(
        &mut paths,
        &profile.filesystem.allow,
        AccessMode::ReadWrite,
        ProfilePathKind::Path,
        context,
    );
    add_profile_paths(
        &mut paths,
        &profile.filesystem.read,
        AccessMode::Read,
        ProfilePathKind::Path,
        context,
    );
    add_profile_paths(
        &mut paths,
        &profile.filesystem.write,
        AccessMode::Write,
        ProfilePathKind::Path,
        context,
    );
    add_profile_paths(
        &mut paths,
        &profile.filesystem.allow_file,
        AccessMode::ReadWrite,
        ProfilePathKind::File,
        context,
    );
    add_profile_paths(
        &mut paths,
        &profile.filesystem.read_file,
        AccessMode::Read,
        ProfilePathKind::File,
        context,
    );
    add_profile_paths(
        &mut paths,
        &profile.filesystem.write_file,
        AccessMode::Write,
        ProfilePathKind::File,
        context,
    );
    Ok(ProfilePolicy {
        paths,
        block_network: profile.network.block,
    })
}

fn add_profile_paths(
    paths: &mut Vec<ProfilePath>,
    values: &[String],
    mode: AccessMode,
    kind: ProfilePathKind,
    context: &ProfileContext,
) {
    paths.extend(values.iter().map(|path| ProfilePath {
        path: super::expand_path(path, context),
        mode,
        kind,
    }));
}

fn workdir_access_mode(value: &str) -> anyhow::Result<Option<AccessMode>> {
    Ok(match value {
        "read" => Some(AccessMode::Read),
        "write" => Some(AccessMode::Write),
        "readwrite" => Some(AccessMode::ReadWrite),
        "none" | "" => None,
        value => return Err(anyhow::anyhow!("unknown profile workdir access: {value}")),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profile_policy_expands_workdir_and_file_rules() {
        let temp =
            tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let context = ProfileContext {
            home: temp.path().join("home"),
            workdir: temp.path().join("work"),
        };
        let profile: AgentProfile = serde_json::from_str(
            r#"{
  "filesystem": {
    "read": ["$WORKDIR/docs"],
    "write_file": ["~/state.json"]
  },
  "workdir": { "access": "readwrite" },
  "network": { "block": true }
}"#,
        )
        .unwrap_or_else(|error| panic!("failed to parse profile: {error}"));

        let policy = profile_policy(&profile, &context)
            .unwrap_or_else(|error| panic!("failed to build profile policy: {error}"));

        assert!(policy.block_network);
        assert_eq!(
            policy.paths,
            vec![
                ProfilePath {
                    path: context.workdir.clone(),
                    mode: AccessMode::ReadWrite,
                    kind: ProfilePathKind::Path,
                },
                ProfilePath {
                    path: context.workdir.join("docs"),
                    mode: AccessMode::Read,
                    kind: ProfilePathKind::Path,
                },
                ProfilePath {
                    path: context.home.join("state.json"),
                    mode: AccessMode::Write,
                    kind: ProfilePathKind::File,
                },
            ]
        );
    }
}
