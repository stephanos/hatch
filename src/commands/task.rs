use clap::{Parser, Subcommand};

#[derive(Debug, Subcommand)]
pub enum TaskCommand {
    List(TaskListArgs),
    #[command(name = "new")]
    New(TaskNewArgs),
    Open(TaskOpenArgs),
    Delete(TaskOpenArgs),
}

#[derive(Debug, Parser)]
pub struct TaskListArgs {
    pub(crate) project: Option<String>,
}

#[derive(Debug, Parser)]
pub struct TaskNewArgs {
    pub(crate) project: String,
    pub(crate) task: String,
}

#[derive(Debug, Parser)]
pub struct TaskOpenArgs {
    pub(crate) query: String,
}

pub(crate) fn run(command: TaskCommand) -> anyhow::Result<()> {
    match command {
        TaskCommand::List(args) => {
            let service = super::workspace_service()?;
            let mut tasks = service.list_tasks_in_workspace()?;
            if let Some(project) = &args.project {
                tasks.retain(|task| &task.project == project);
            }
            for task in tasks {
                println!("{}/{}", task.project, task.task);
            }
            Ok(())
        }
        TaskCommand::New(args) => {
            let service = super::workspace_service()?;
            let request = hatch::TaskCreateRequest {
                project: args.project,
                task: args.task,
            };
            service.create_task_in_workspace(request)?;
            Ok(())
        }
        TaskCommand::Open(args) => {
            let service = super::workspace_service()?;
            service.open_task_by_query_in_workspace(&args.query)?;
            Ok(())
        }
        TaskCommand::Delete(args) => {
            let service = super::workspace_service()?;
            let task = service.delete_task_in_workspace(&args.query)?;
            println!("{}", task.path);
            Ok(())
        }
    }
}
