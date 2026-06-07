use clap::{Parser, Subcommand};

use hatch::AddRepoRequest;

#[derive(Debug, Subcommand)]
pub enum RepoCommand {
    #[command(name = "new")]
    New(NewRepoArgs),
}

#[derive(Debug, Parser)]
pub struct NewRepoArgs {
    pub(crate) repo: String,
    /// Task directory to create the repo under.
    pub(crate) task_path: Option<String>,
    #[arg(long = "task-path")]
    pub(crate) task_path_flag: Option<String>,
    #[arg(long = "base-branch")]
    pub(crate) base_branch: Option<String>,
    #[arg(long = "dir")]
    pub(crate) checkout_dir: Option<String>,
    #[arg(long)]
    pub(crate) force: bool,
}

pub(crate) fn run(command: RepoCommand) -> anyhow::Result<()> {
    match command {
        RepoCommand::New(args) => run_new_repo_command(args),
    }
}

fn run_new_repo_command(args: NewRepoArgs) -> anyhow::Result<()> {
    let service = super::workspace_service()?;
    let request = AddRepoRequest {
        repo: args.repo,
        task_path: args
            .task_path_flag
            .or(args.task_path)
            .unwrap_or_else(|| ".".to_string())
            .into(),
        checkout_dir: args.checkout_dir,
        base_branch: args.base_branch,
        force: args.force,
    };
    service.add_repo_in_workspace(request)?;
    Ok(())
}
