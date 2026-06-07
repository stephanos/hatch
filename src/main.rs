use clap::{
    Command, CommandFactory, Parser,
    error::{ContextKind, ContextValue, ErrorKind},
};

use commands::Args;

mod commands;

fn main() {
    let args = match Args::try_parse() {
        Ok(args) => args,
        Err(error) => {
            if matches!(
                error.kind(),
                ErrorKind::DisplayHelp | ErrorKind::DisplayVersion
            ) {
                print_help_or_version(error);
                std::process::exit(0);
            }
            print_parse_error(error);
            std::process::exit(2);
        }
    };
    if args.command.is_none() {
        match workspace_state() {
            Ok((paths, false)) => hatch::terminal::print_workspace_setup_prompt(&paths),
            Ok((paths, true)) => {
                let mut command = Args::command();
                hatch::terminal::print_help_with_workspace(&mut command, &paths);
            }
            Err(error) => {
                hatch::terminal::print_error(error);
                std::process::exit(1);
            }
        }
        std::process::exit(0);
    }
    if let Err(error) = commands::run(args) {
        hatch::terminal::print_error(error);
        std::process::exit(1);
    }
}

fn print_parse_error(error: clap::Error) {
    if error.kind() != ErrorKind::UnknownArgument {
        hatch::terminal::print_error(error);
        return;
    }
    hatch::terminal::print_error(unknown_argument_message(&error));
    eprintln!();
    let (mut command, path) = current_command();
    let bin_name = std::iter::once("hatch".to_string())
        .chain(path)
        .collect::<Vec<_>>()
        .join(" ");
    command = command.bin_name(bin_name);
    eprint!("{}", command.render_help());
}

fn unknown_argument_message(error: &clap::Error) -> String {
    if let Some(ContextValue::String(argument)) = error.get(ContextKind::InvalidArg) {
        return format!("unexpected argument '{argument}' found");
    }
    let message = error.to_string();
    message
        .lines()
        .next()
        .unwrap_or("unexpected argument found")
        .strip_prefix("error: ")
        .unwrap_or("unexpected argument found")
        .to_string()
}

fn current_command() -> (Command, Vec<String>) {
    let command = Args::command();
    let path = current_command_path(&command);
    (command_at_path(&command, &path), path)
}

fn command_at_path(command: &Command, path: &[String]) -> Command {
    let Some((name, rest)) = path.split_first() else {
        return command.clone();
    };
    let Some(subcommand) = command.find_subcommand(name) else {
        return command.clone();
    };
    command_at_path(subcommand, rest)
}

fn current_command_path(command: &Command) -> Vec<String> {
    let mut path = Vec::new();
    let mut current = command;
    for arg in std::env::args_os().skip(1) {
        if arg.to_string_lossy().starts_with('-') {
            break;
        }
        let Some(subcommand) = current.find_subcommand(&arg) else {
            break;
        };
        path.push(subcommand.get_name().to_string());
        current = subcommand;
    }
    path
}

fn print_help_or_version(error: clap::Error) {
    print!("{error}");
    if error.kind() != ErrorKind::DisplayHelp {
        return;
    }
    let Ok((paths, true)) = workspace_state() else {
        println!();
        return;
    };
    hatch::terminal::print_workspace_path(&paths);
}

fn workspace_state() -> hatch::Result<(hatch::AppPaths, bool)> {
    hatch::WorkspaceService::from_env().map(|service| {
        let paths = service.paths()?;
        let initialized = paths.hatch_root.exists();
        Ok((paths, initialized))
    })?
}
