use clap::{Parser, Subcommand};

#[derive(Debug, Subcommand)]
pub enum HookCommand {
    Workspace(HookWorkspaceArgs),
}

#[derive(Debug, Parser)]
pub struct HookWorkspaceArgs {
    pub(crate) hook: String,
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub(crate) args: Vec<String>,
}

pub(crate) fn run(command: HookCommand) -> anyhow::Result<()> {
    match command {
        HookCommand::Workspace(args) => {
            let service = super::workspace_service()?;
            service.run_workspace_hook_in_workspace(&args.hook, args.args)?;
            Ok(())
        }
    }
}
