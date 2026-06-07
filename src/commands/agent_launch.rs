use anyhow::Context;
use camino::Utf8PathBuf;
use clap::Parser;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Parser)]
pub struct AgentLaunchArgs {
    pub(crate) agent: String,
    #[arg(long = "workspace-root")]
    pub(crate) workspace_root: Utf8PathBuf,
    #[arg(long = "scope-path")]
    pub(crate) scope_path: Utf8PathBuf,
    #[arg(last = true)]
    pub(crate) args: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct AgentLaunchPlan {
    program: String,
    profile: Option<String>,
    profile_cache: Option<PathBuf>,
    allow: Utf8PathBuf,
    args: Vec<String>,
}

pub(crate) fn run(args: AgentLaunchArgs) -> anyhow::Result<()> {
    let plan = launch_plan(args.agent, args.workspace_root, args.scope_path, args.args);
    let hatch = std::env::current_exe().context("failed to resolve hatch executable")?;
    exec_agent_exec(&hatch, plan)
}

fn launch_plan(
    agent: String,
    workspace_root: Utf8PathBuf,
    scope_path: Utf8PathBuf,
    args: Vec<String>,
) -> AgentLaunchPlan {
    let profile = match agent.as_str() {
        "codex" => Some("always-further/codex".to_string()),
        "claude" => Some("always-further/claude".to_string()),
        _ => None,
    };
    let profile_cache = profile
        .as_ref()
        .map(|_| workspace_root.join(".hatch/cache/nono").into_std_path_buf());
    AgentLaunchPlan {
        program: agent,
        profile,
        profile_cache,
        allow: scope_path,
        args,
    }
}

fn agent_exec_args(plan: &AgentLaunchPlan) -> Vec<String> {
    let mut args = vec!["__agent-exec".to_string(), plan.program.clone()];
    if let Some(profile) = &plan.profile {
        args.push("--profile".to_string());
        args.push(profile.clone());
    }
    if let Some(profile_cache) = &plan.profile_cache {
        args.push("--profile-cache".to_string());
        args.push(profile_cache.display().to_string());
    }
    args.push("--allow".to_string());
    args.push(plan.allow.to_string());
    if !plan.args.is_empty() {
        args.push("--".to_string());
        args.extend(plan.args.iter().cloned());
    }
    args
}

#[cfg(unix)]
fn exec_agent_exec(hatch: &std::path::Path, plan: AgentLaunchPlan) -> anyhow::Result<()> {
    use std::os::unix::process::CommandExt;

    let args = agent_exec_args(&plan);
    let error = Command::new(hatch).args(args).exec();
    Err(anyhow::anyhow!(
        "failed to exec {} __agent-exec: {error}",
        hatch.display()
    ))
}

#[cfg(not(unix))]
fn exec_agent_exec(hatch: &std::path::Path, plan: AgentLaunchPlan) -> anyhow::Result<()> {
    let args = agent_exec_args(&plan);
    let status = Command::new(hatch)
        .args(args)
        .status()
        .with_context(|| format!("failed to start {} __agent-exec", hatch.display()))?;
    if status.success() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(
            "{} __agent-exec exited with {status}",
            hatch.display()
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_launch_plan_uses_registry_profile_and_workspace_cache() {
        let workspace = Utf8PathBuf::from("/workspace");
        let scope = Utf8PathBuf::from("/workspace/api/task");

        let plan = launch_plan(
            "codex".to_string(),
            workspace.clone(),
            scope.clone(),
            vec!["--version".to_string()],
        );

        assert_eq!(
            plan,
            AgentLaunchPlan {
                program: "codex".to_string(),
                profile: Some("always-further/codex".to_string()),
                profile_cache: Some(PathBuf::from("/workspace/.hatch/cache/nono")),
                allow: scope,
                args: vec!["--version".to_string()],
            }
        );
        assert_eq!(
            agent_exec_args(&plan),
            vec![
                "__agent-exec",
                "codex",
                "--profile",
                "always-further/codex",
                "--profile-cache",
                "/workspace/.hatch/cache/nono",
                "--allow",
                "/workspace/api/task",
                "--",
                "--version",
            ]
        );
    }

    #[test]
    fn custom_launch_plan_only_allows_scope() {
        let plan = launch_plan(
            "custom".to_string(),
            Utf8PathBuf::from("/workspace"),
            Utf8PathBuf::from("/workspace"),
            Vec::new(),
        );

        assert_eq!(
            agent_exec_args(&plan),
            vec!["__agent-exec", "custom", "--allow", "/workspace"]
        );
    }
}
