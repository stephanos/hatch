use anstyle::{AnsiColor, Effects, Style};
use clap::Command;
use std::io::Write;

use crate::AppPaths;

pub(crate) const HOOK_STATUS_COLOR_ENV: &str = "HATCH_HOOK_STATUS_COLOR";
pub(crate) const HOOK_STATUS_COLOR_ALWAYS: &str = "always";

pub fn print_error(error: impl std::fmt::Display) {
    let message = error.to_string();
    let message = message.strip_prefix("error: ").unwrap_or(&message);
    anstream::eprintln!(
        "{}error:{} {message}",
        error_style().render(),
        error_style().render_reset()
    );
}

pub fn print_workspace_setup_prompt(paths: &AppPaths) {
    let style = setup_prompt_style();
    let mut stream =
        anstream::AutoStream::new(std::io::stdout(), anstream::ColorChoice::AlwaysAnsi);
    writeln!(
        stream,
        "{style}\
========================================
No hatch workspace found
========================================

Start in the folder you want to use:

  cd {workspace_root}
  hatch workspace new .

Then create your first project and task:

  hatch project new <project>
  hatch task new <project> <task>
{reset}",
        style = style.render(),
        reset = style.render_reset(),
        workspace_root = paths.workspace_root
    )
    .expect("failed to write workspace setup prompt");
}

pub fn print_help_with_workspace(command: &mut Command, paths: &AppPaths) {
    anstream::print!("{}", command.render_help());
    print_workspace_path(paths);
}

pub fn print_workspace_path(paths: &AppPaths) {
    anstream::println!();
    anstream::println!("Workspace: {}", paths.workspace_root);
    anstream::println!();
}

pub fn print_hook_status(hook_file: impl std::fmt::Display) {
    let color_choice = match std::env::var(HOOK_STATUS_COLOR_ENV).as_deref() {
        Ok(HOOK_STATUS_COLOR_ALWAYS) => anstream::ColorChoice::AlwaysAnsi,
        _ => anstream::ColorChoice::Auto,
    };
    let mut stream = anstream::AutoStream::new(std::io::stderr(), color_choice);
    writeln!(
        stream,
        "{}running hook:{} {hook_file}",
        hook_style().render(),
        hook_style().render_reset()
    )
    .expect("failed to write hook status");
}

fn error_style() -> Style {
    AnsiColor::Red.on_default()
}

fn hook_style() -> Style {
    AnsiColor::BrightBlack.on_default().effects(Effects::ITALIC)
}

fn setup_prompt_style() -> Style {
    AnsiColor::Yellow.on_default().effects(Effects::BOLD)
}
