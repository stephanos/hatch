use clap::{Parser, Subcommand};

#[derive(Debug, Subcommand)]
pub enum AgentCommand {
    Start(AgentStartArgs),
}

#[derive(Debug, Parser)]
pub struct AgentStartArgs {
    pub(crate) agent: String,
    #[arg(last = true)]
    pub(crate) args: Vec<String>,
}

pub(crate) fn run(command: AgentCommand) -> anyhow::Result<()> {
    match command {
        AgentCommand::Start(args) => {
            let service = super::workspace_service()?;
            service.start_agent_in_workspace(args.agent, args.args)?;
            Ok(())
        }
    }
}
