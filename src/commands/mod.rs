use anyhow::{Context, anyhow};
use camino::Utf8PathBuf;
use clap::{Parser, Subcommand};
use std::process::{Command as StdCommand, Stdio};

mod agent;
mod agent_exec;
mod agent_profile;
mod agent_sandbox;
mod completion;
mod hook;
mod project;
mod repo;
mod task;
mod update;
mod version;
mod workspace;

use hatch::WorkspaceService;

pub use agent::AgentCommand;
pub use agent_exec::AgentExecArgs;
pub use completion::{CarapaceCompleteArgs, CompleteArgs, CompletionsArgs};
pub use hook::HookCommand;
pub use project::ProjectCommand;
pub use repo::RepoCommand;
pub use task::TaskCommand;
pub use update::{UpdateArgs, run_update};
pub use workspace::WorkspaceCommand;

#[derive(Debug, Parser)]
#[command(name = "hatch")]
#[command(about = "CLI for AI-driven git workspace management")]
pub struct Args {
    #[command(subcommand)]
    pub(crate) command: Option<Command>,
}

#[derive(Debug, Subcommand)]
pub(crate) enum Command {
    Workspace {
        #[command(subcommand)]
        command: WorkspaceCommand,
    },
    Project {
        #[command(subcommand)]
        command: ProjectCommand,
    },
    Task {
        #[command(subcommand)]
        command: TaskCommand,
    },
    Repo {
        #[command(subcommand)]
        command: RepoCommand,
    },
    Agent {
        #[command(subcommand)]
        command: AgentCommand,
    },
    #[command(hide = true)]
    Hook {
        #[command(subcommand)]
        command: HookCommand,
    },
    #[command(name = "update")]
    Update(UpdateArgs),
    Version,
    Completions(CompletionsArgs),
    #[command(name = "complete", hide = true)]
    CarapaceComplete(CarapaceCompleteArgs),
    #[command(name = "__complete", hide = true)]
    Complete(CompleteArgs),
    #[command(name = "__agent-exec", hide = true)]
    AgentExec(AgentExecArgs),
}

pub fn run(args: Args) -> anyhow::Result<()> {
    check_runtime_requirements()?;
    let Some(command) = args.command else {
        return Ok(());
    };
    match command {
        Command::Completions(args) => completion::run(args),
        Command::CarapaceComplete(args) => {
            completion::run_complete_command(&args.words, args.index)
        }
        Command::Complete(args) => {
            if args.with_markers {
                completion::run_complete_command_with_markers(&args.words, args.current)
            } else if args.with_description {
                completion::run_complete_command_with_description(&args.words, args.current)
            } else {
                completion::run_complete_command(&args.words, args.current)
            }
        }
        Command::Workspace { command } => workspace::run(command),
        Command::Project { command } => project::run(command),
        Command::Task { command } => task::run(command),
        Command::Repo { command } => repo::run(command),
        Command::Agent { command } => agent::run(command),
        Command::Hook { command } => hook::run(command),
        Command::Update(args) => run_update(args),
        Command::Version => version::run(),
        Command::AgentExec(args) => agent_exec::run(args),
    }
}

fn workspace_service() -> anyhow::Result<WorkspaceService> {
    WorkspaceService::from_env().context("failed to load hatch environment")
}

fn workspace_service_at(path: Utf8PathBuf) -> anyhow::Result<WorkspaceService> {
    Ok(WorkspaceService::new(hatch::HatchStore::new(
        hatch::HatchEnvironment::for_workspace_init(path),
    )))
}

fn check_runtime_requirements() -> anyhow::Result<()> {
    let requirements = [
        ("git", "https://git-scm.com/downloads"),
        ("gh", "https://cli.github.com/"),
    ];

    let missing = requirements
        .iter()
        .filter_map(|(name, website)| {
            if has_command(name) {
                None
            } else {
                Some(((*name).to_string(), (*website).to_string()))
            }
        })
        .collect::<Vec<_>>();

    if missing.is_empty() {
        return Ok(());
    }

    let mut message = String::from("missing required tools:\n");
    for (name, website) in missing {
        message.push_str(&format!("  - {name} ({website})\n"));
    }
    message.push_str("Please install these tools before running hatch.");
    Err(anyhow!(message))
}

fn has_command(name: &str) -> bool {
    StdCommand::new(name)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}
