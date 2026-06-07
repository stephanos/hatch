use clap::{Parser, Subcommand};
use std::io::Write;

#[derive(Debug, Subcommand)]
pub enum ProjectCommand {
    List,
    #[command(name = "new")]
    New(ProjectNewArgs),
    Clean(ProjectNameArgs),
    Delete(ProjectNameArgs),
}

#[derive(Debug, Parser)]
pub struct ProjectNameArgs {
    pub(crate) project: String,
}

#[derive(Debug, Parser)]
pub struct ProjectNewArgs {
    #[arg(long)]
    pub(crate) force: bool,
    pub(crate) name: String,
}

pub(crate) fn run(command: ProjectCommand) -> anyhow::Result<()> {
    match command {
        ProjectCommand::List => {
            let service = super::workspace_service()?;
            let projects = service.list_projects_in_workspace()?;
            for project in projects {
                println!("{}", project.name);
            }
            Ok(())
        }
        ProjectCommand::New(args) => {
            let service = super::workspace_service()?;
            let request = hatch::ProjectCreateRequest {
                name: args.name,
                force: args.force,
            };
            let project = service.create_project_in_workspace(request)?;
            println!("{}", project.path);
            Ok(())
        }
        ProjectCommand::Clean(args) => {
            let service = super::workspace_service()?;
            let candidates_view =
                service.cleanup_candidates_with_view_for_project_in_workspace(&args.project)?;
            if candidates_view.is_empty() {
                println!("No cleanup candidates");
                return Ok(());
            }

            let selected = super::workspace::interactive_cleanup_selection(&candidates_view)?;
            if selected.is_empty() {
                println!("No tasks selected for cleanup");
                return Ok(());
            }

            let removed = service.cleanup_selected_tasks_in_workspace(&selected)?;
            super::workspace::write_cleanup_human(&removed);
            Ok(())
        }
        ProjectCommand::Delete(args) => {
            let service = super::workspace_service()?;
            let (project, tasks) = service.project_delete_preview_in_workspace(&args.project)?;
            if !tasks.is_empty() {
                anstream::eprintln!("{} contains tasks:", project.name);
                for task in &tasks {
                    anstream::eprintln!("  - {}", task.id);
                }
                if !confirm_project_delete(&project.name)? {
                    anstream::eprintln!("Project deletion cancelled");
                    return Ok(());
                }
            }
            let deleted = service.delete_project_in_workspace(&project.name)?;
            println!("{}", deleted.path);
            Ok(())
        }
    }
}

fn confirm_project_delete(project: &str) -> anyhow::Result<bool> {
    anstream::eprint!("Delete project {project}? [Y/n] ");
    std::io::stderr().flush()?;
    let mut response = String::new();
    let bytes = std::io::stdin().read_line(&mut response)?;
    if bytes == 0 {
        return Ok(false);
    }
    let response = response.trim();
    Ok(response.is_empty()
        || response.eq_ignore_ascii_case("y")
        || response.eq_ignore_ascii_case("yes"))
}
