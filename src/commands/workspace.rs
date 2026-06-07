use camino::Utf8PathBuf;
use clap::Subcommand;
use skim::prelude::*;
use std::borrow::Cow;
use std::collections::BTreeSet;
use std::io::{self, IsTerminal};

#[derive(Debug, Subcommand)]
pub enum WorkspaceCommand {
    #[command(name = "new")]
    New {
        #[arg(
            value_name = "PATH",
            help = "Workspace directory; use . for the current directory"
        )]
        path: Utf8PathBuf,
        #[arg(long)]
        force: bool,
    },
    Root,
    Clean,
}

pub(crate) fn run(command: WorkspaceCommand) -> anyhow::Result<()> {
    match command {
        WorkspaceCommand::New { path, force } => {
            let service = super::workspace_service_at(resolve_workspace_path(path)?)?;
            service.create_workspace(force)?;
            println!("Initialized workspace");
            Ok(())
        }
        WorkspaceCommand::Root => {
            let service = super::workspace_service()?;
            println!("{}", service.paths()?.workspace_root);
            Ok(())
        }
        WorkspaceCommand::Clean => {
            let service = super::workspace_service()?;
            let candidates_view = service.cleanup_candidates_with_view_in_workspace()?;
            if candidates_view.is_empty() {
                println!("No cleanup candidates");
                return Ok(());
            }

            let selected = interactive_cleanup_selection(&candidates_view)?;
            if selected.is_empty() {
                println!("No tasks selected for cleanup");
                return Ok(());
            }

            let removed = service.cleanup_selected_tasks_in_workspace(&selected)?;
            write_cleanup_human(&removed);
            Ok(())
        }
    }
}

fn resolve_workspace_path(path: Utf8PathBuf) -> anyhow::Result<Utf8PathBuf> {
    if path.is_absolute() {
        return Ok(path);
    }
    let current_dir = Utf8PathBuf::from_path_buf(std::env::current_dir()?)
        .map_err(|path| anyhow::anyhow!("cwd is not valid UTF-8: {}", path.display()))?;
    Ok(current_dir.join(path))
}

pub(crate) fn interactive_cleanup_selection(
    candidates: &[hatch::CleanupCandidateView],
) -> anyhow::Result<Vec<hatch::CleanupCandidate>> {
    if candidates.is_empty() {
        println!("No cleanup candidates");
        return Ok(Vec::new());
    }
    if !io::stdin().is_terminal() {
        return Ok(Vec::new());
    }

    let selection_rows = cleanup_selection_rows(candidates);

    let options = SkimOptionsBuilder::default()
        .multi(true)
        .height("80%")
        .prompt("clean ")
        .selector_icon(" ")
        .multi_select_icon("[x] ")
        .header("Select tasks to delete")
        .pre_select_items(selection_rows.pre_select_items.join("\n"))
        .bind(["tab:toggle".to_string(), "shift-tab:toggle".to_string()].to_vec())
        .build()
        .map_err(|error| anyhow::anyhow!("failed to create cleanup selector: {error}"))?;
    let output = Skim::run_items(options, selection_rows.items)
        .map_err(|error| anyhow::anyhow!("failed to run cleanup selector: {error}"))?;

    if output.is_abort {
        return Ok(Vec::new());
    }

    let mut selected_indices = BTreeSet::new();
    for item in output.selected_items {
        if let Some(candidate_item) = item
            .item
            .as_any()
            .downcast_ref::<CleanupCandidateFuzzyRow>()
        {
            selected_indices.insert(candidate_item.index);
        }
    }

    if selected_indices.is_empty() {
        return Ok(Vec::new());
    }

    Ok(selected_indices
        .into_iter()
        .map(|index| selection_rows.sorted_candidates[index].candidate.clone())
        .collect())
}

#[derive(Debug)]
struct CleanupSelectionRows {
    sorted_candidates: Vec<hatch::CleanupCandidateView>,
    items: Vec<CleanupCandidateFuzzyRow>,
    pre_select_items: Vec<String>,
}

fn cleanup_selection_rows(candidates: &[hatch::CleanupCandidateView]) -> CleanupSelectionRows {
    let mut sorted_candidates = candidates.to_vec();
    sorted_candidates.sort_by(|left, right| {
        (
            left.candidate.project.as_str(),
            left.candidate.task.as_str(),
        )
            .cmp(&(
                right.candidate.project.as_str(),
                right.candidate.task.as_str(),
            ))
    });

    let (path_width, repo_width, status_width) = {
        let mut path_width = 0usize;
        let mut repo_width = 0usize;
        let mut status_width = 0usize;
        for candidate in &sorted_candidates {
            let path = format!(
                "{}/{}",
                candidate.candidate.project, candidate.candidate.task
            );
            let repos = join_repos(candidate);
            path_width = path_width.max(path.len());
            repo_width = repo_width.max(repos.len());
            status_width = status_width.max(candidate.status.len());
        }
        (path_width, repo_width, status_width)
    };

    let mut pre_select_items = Vec::new();
    let items = sorted_candidates
        .iter()
        .enumerate()
        .map(|(index, candidate)| {
            let path = format!(
                "{}/{}",
                candidate.candidate.project, candidate.candidate.task
            );
            let repos = join_repos(candidate);
            let status = candidate.status.clone();
            let selected = candidate.default_selected;
            let text = format!(
                "{:<path_width$} | {:<repo_width$} | {:<status_width$}",
                path,
                repos,
                status,
                path_width = path_width,
                repo_width = repo_width,
                status_width = status_width
            );
            if selected {
                pre_select_items.push(text.clone());
            }

            CleanupCandidateFuzzyRow { index, text }
        })
        .collect::<Vec<_>>();

    CleanupSelectionRows {
        sorted_candidates,
        items,
        pre_select_items,
    }
}

#[derive(Debug)]
struct CleanupCandidateFuzzyRow {
    index: usize,
    text: String,
}

impl skim::SkimItem for CleanupCandidateFuzzyRow {
    fn text(&self) -> Cow<'_, str> {
        Cow::Owned(self.text.clone())
    }
}

fn join_repos(candidate: &hatch::CleanupCandidateView) -> String {
    if candidate.repos.is_empty() {
        "No repos".to_string()
    } else {
        candidate.repos.join(", ")
    }
}

pub(crate) fn write_cleanup_human(candidates: &[hatch::CleanupCandidate]) {
    if candidates.is_empty() {
        println!("No cleanup candidates");
        return;
    }
    for candidate in candidates {
        let action = if cfg!(target_os = "macos") {
            "Moved to trash"
        } else {
            "Removed"
        };
        println!(
            "{action} {}/{} ({})",
            candidate.project,
            candidate.task,
            candidate.reasons.join(", ")
        );
    }
}

#[cfg(test)]
mod tests {
    use super::cleanup_selection_rows;
    use camino::Utf8PathBuf;

    fn candidate(
        project: &str,
        task: &str,
        repos: &[&str],
        status: &str,
        selected: bool,
    ) -> hatch::CleanupCandidateView {
        hatch::CleanupCandidateView {
            candidate: hatch::CleanupCandidate {
                project: project.to_string(),
                task: task.to_string(),
                path: Utf8PathBuf::from(format!("{project}/{task}")),
                reasons: Vec::new(),
            },
            repos: repos.iter().map(|repo| (*repo).to_string()).collect(),
            status: status.to_string(),
            default_selected: selected,
        }
    }

    #[test]
    fn formats_cleanup_selection_rows_sorted_with_preselected_items() {
        let rows = cleanup_selection_rows(&[
            candidate("web", "z-done", &[], "NO_PR", false),
            candidate(
                "api",
                "done",
                &["backend", "frontend"],
                "GH_RATE_LIMITED",
                false,
            ),
            candidate("api", "closed", &["backend"], "CLOSED", true),
        ]);

        let text = rows
            .items
            .iter()
            .map(|row| row.text.clone())
            .collect::<Vec<_>>();

        assert_eq!(
            text,
            vec![
                "api/closed | backend           | CLOSED         ",
                "api/done   | backend, frontend | GH_RATE_LIMITED",
                "web/z-done | No repos          | NO_PR          ",
            ]
        );
        assert_eq!(
            rows.pre_select_items,
            vec!["api/closed | backend           | CLOSED         ".to_string()]
        );
        assert_eq!(rows.sorted_candidates[0].candidate.task, "closed");
        assert_eq!(rows.sorted_candidates[1].candidate.task, "done");
        assert_eq!(rows.sorted_candidates[2].candidate.project, "web");
    }
}
