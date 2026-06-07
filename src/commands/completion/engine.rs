use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone)]
pub(super) struct CompletionCandidate {
    pub(super) value: String,
    pub(super) description: Option<String>,
    pub(super) marker: Option<String>,
}

pub(super) fn complete_candidates(words: &[String], current: usize) -> Vec<CompletionCandidate> {
    let (words, current) = normalize_completion_words(words, current);
    if words.is_empty() {
        return static_completions(top_level_commands(), "");
    }
    let current_token = words.get(current).map(String::as_str).unwrap_or("");
    if current == 0
        && words.len() == 1
        && let Some(subcommands) = top_level_subcommands(words[0].as_str())
    {
        return static_completions(subcommands.iter().map(|value| value.to_string()), "");
    }

    if current == 0 {
        return static_completions(top_level_commands(), current_token);
    }
    let first = words[0].as_str();
    let second = words.get(1).map(String::as_str).unwrap_or("");
    match first {
        "completions" if current <= 1 => static_completions(
            ["bash", "fish", "zsh"]
                .iter()
                .map(std::string::ToString::to_string),
            current_token,
        ),
        "repo" => match current {
            1 => static_completions(
                ["new", "help"].iter().map(std::string::ToString::to_string),
                current_token,
            ),
            2 if second == "new" => Vec::new(),
            _ => Vec::new(),
        },
        "project" => match current {
            1 => static_completions(
                ["list", "new", "clean", "delete", "help"]
                    .iter()
                    .map(std::string::ToString::to_string),
                current_token,
            ),
            2 if second == "clean" => project_name_candidates(current_token),
            2 if second == "delete" => project_name_candidates(current_token),
            _ => Vec::new(),
        },
        "task" => match current {
            1 if second == "open" && current_token == "open" => task_candidates(""),
            1 => static_completions(
                ["list", "new", "open", "delete", "help"]
                    .iter()
                    .map(std::string::ToString::to_string),
                current_token,
            ),
            2 if second == "new" => project_name_candidates(current_token),
            2 if second == "list" => project_name_candidates(current_token),
            2 if second == "open" => task_candidates(current_token),
            2 if second == "delete" => task_candidates(current_token),
            3 if second == "delete" => task_candidates(current_token),
            _ => Vec::new(),
        },
        "workspace" => match current {
            1 => static_completions(
                ["new", "root", "clean", "help"]
                    .iter()
                    .map(std::string::ToString::to_string),
                current_token,
            ),
            2 if second == "new" => directory_candidates(current_token),
            _ => Vec::new(),
        },
        "version" => Vec::new(),
        _ => Vec::new(),
    }
}

fn top_level_commands() -> impl Iterator<Item = String> {
    [
        "workspace",
        "project",
        "task",
        "repo",
        "update",
        "version",
        "completions",
        "help",
    ]
    .iter()
    .map(std::string::ToString::to_string)
}

fn top_level_subcommands(command: &str) -> Option<&'static [&'static str]> {
    match command {
        "workspace" => Some(&["new", "root", "clean", "help"]),
        "project" => Some(&["list", "new", "clean", "delete", "help"]),
        "task" => Some(&["list", "new", "open", "delete", "help"]),
        "repo" => Some(&["new", "help"]),
        _ => None,
    }
}

fn normalize_completion_words(words: &[String], current: usize) -> (Vec<String>, usize) {
    if words.is_empty() {
        return (Vec::new(), 0);
    }

    let is_hatch_token = |word: &str| -> bool {
        word == "hatch"
            || Path::new(word)
                .file_name()
                .map(|name| name == "hatch")
                .unwrap_or(false)
    };

    let is_hatch = words
        .first()
        .map(|word| is_hatch_token(word.as_str()))
        .unwrap_or(false);

    let normalized = if is_hatch {
        let normalized_current = current.saturating_sub(1);
        (words[1..].to_vec(), normalized_current)
    } else if current >= 1
        && words
            .get(1)
            .map(|word| is_hatch_token(word.as_str()))
            .unwrap_or(false)
    {
        let normalized_current = current.saturating_sub(2);
        (words[2..].to_vec(), normalized_current)
    } else {
        (words.to_vec(), current)
    };
    let mut normalized_index = normalized.1.min(normalized.0.len());
    if normalized_index > 0
        && normalized_index == normalized.0.len()
        && normalized
            .0
            .last()
            .map(|word| word.is_empty())
            .unwrap_or(false)
    {
        normalized_index = normalized_index.saturating_sub(1);
    }
    if normalized.0.is_empty() {
        normalized_index = 0;
    }
    (normalized.0, normalized_index)
}

fn static_completions<I>(values: I, current: &str) -> Vec<CompletionCandidate>
where
    I: IntoIterator<Item = String>,
{
    if current.is_empty() {
        return values
            .into_iter()
            .map(|value| CompletionCandidate {
                value,
                description: None,
                marker: None,
            })
            .collect();
    }
    let current_lower = current.to_lowercase();
    values
        .into_iter()
        .filter_map(|value| {
            if value.to_lowercase().starts_with(&current_lower) {
                Some(CompletionCandidate {
                    value,
                    description: None,
                    marker: None,
                })
            } else {
                None
            }
        })
        .collect()
}

fn directory_candidates(current: &str) -> Vec<CompletionCandidate> {
    let (search_dir, render_prefix, name_prefix) = directory_completion_parts(current);
    let Ok(entries) = fs_err::read_dir(&search_dir) else {
        return Vec::new();
    };
    let include_hidden = name_prefix.starts_with('.');
    let mut candidates = entries
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let file_type = entry.file_type().ok()?;
            if !file_type.is_dir() {
                return None;
            }
            let name = entry.file_name().into_string().ok()?;
            if !include_hidden && name.starts_with('.') {
                return None;
            }
            if !name.starts_with(name_prefix) {
                return None;
            }
            Some(CompletionCandidate {
                value: format!("{render_prefix}{name}/"),
                description: None,
                marker: None,
            })
        })
        .collect::<Vec<_>>();
    candidates.sort_by(|left, right| left.value.cmp(&right.value));
    candidates
}

fn directory_completion_parts(current: &str) -> (PathBuf, String, &str) {
    if current.is_empty() {
        return (PathBuf::from("."), String::new(), "");
    }
    if current.ends_with('/') {
        return (completion_search_dir(current), current.to_string(), "");
    }
    if let Some(index) = current.rfind('/') {
        let directory = &current[..index];
        let render_prefix = current[..=index].to_string();
        let name_prefix = &current[index + 1..];
        let search = if directory.is_empty() {
            PathBuf::from("/")
        } else {
            completion_search_dir(directory)
        };
        return (search, render_prefix, name_prefix);
    }
    (PathBuf::from("."), String::new(), current)
}

fn completion_search_dir(value: &str) -> PathBuf {
    if value == "~" {
        return std::env::var_os("HOME").map_or_else(|| PathBuf::from(value), PathBuf::from);
    }
    if let Some(rest) = value.strip_prefix("~/")
        && let Some(home) = std::env::var_os("HOME")
    {
        return PathBuf::from(home).join(rest);
    }
    PathBuf::from(value)
}

fn project_name_candidates(current: &str) -> Vec<CompletionCandidate> {
    let service = super::super::workspace_service().ok();
    let Some(service) = service else {
        return Vec::new();
    };
    let paths = service.paths().ok();
    let Some(paths) = paths else {
        return Vec::new();
    };
    let projects = match service.list_projects(&paths) {
        Ok(projects) => projects,
        Err(_) => return Vec::new(),
    };
    let candidates = projects
        .into_iter()
        .map(|project| (project.name, None))
        .collect::<Vec<_>>();
    fuzzy_suggestions(current, candidates)
}

fn task_candidates(current: &str) -> Vec<CompletionCandidate> {
    let service = super::super::workspace_service().ok();
    let Some(service) = service else {
        return Vec::new();
    };
    let paths = service.paths().ok();
    let Some(paths) = paths else {
        return Vec::new();
    };
    let tasks = match service.list_tasks(&paths) {
        Ok(tasks) => tasks,
        Err(_) => return Vec::new(),
    };
    if current.is_empty() {
        return recent_task_candidates(tasks);
    }
    let candidates = tasks
        .into_iter()
        .map(|task| (task.id, None))
        .collect::<Vec<_>>();
    fuzzy_suggestions(current, candidates)
}

fn recent_task_candidates(mut tasks: Vec<hatch::TaskSummary>) -> Vec<CompletionCandidate> {
    tasks.sort_by(|left, right| {
        task_created_at(right)
            .cmp(&task_created_at(left))
            .then_with(|| left.id.cmp(&right.id))
    });
    tasks
        .into_iter()
        .enumerate()
        .map(|(index, task)| CompletionCandidate {
            value: task.id,
            description: None,
            marker: (index == 0).then(|| "default".to_string()),
        })
        .collect()
}

fn task_created_at(task: &hatch::TaskSummary) -> Option<SystemTime> {
    let metadata = fs_err::metadata(&task.path).ok()?;
    metadata.created().or_else(|_| metadata.modified()).ok()
}

fn fuzzy_suggestions(
    current: &str,
    candidates: Vec<(String, Option<String>)>,
) -> Vec<CompletionCandidate> {
    let ranked = hatch::matching::rank_fuzzy(current, candidates, |candidate| &candidate.0);
    let top_score = ranked.first().map(|ranked| ranked.score);
    let ambiguous_top_count = top_score
        .map(|score| {
            ranked
                .iter()
                .take_while(|ranked| ranked.score == score)
                .count()
        })
        .unwrap_or(0);
    let current_lower = current.to_lowercase();
    ranked
        .into_iter()
        .enumerate()
        .map(|(index, ranked)| {
            let exact_partial_match = !current_lower.is_empty()
                && ranked
                    .item
                    .0
                    .to_lowercase()
                    .contains(current_lower.as_str());
            let ambiguous_top_match = Some(ranked.score) == top_score && ambiguous_top_count > 1;
            let marker = if ambiguous_top_match || (ambiguous_top_count > 1 && exact_partial_match)
            {
                Some("ambiguous".to_string())
            } else if index == 0 {
                Some("default".to_string())
            } else {
                None
            };
            CompletionCandidate {
                value: ranked.item.0,
                description: ranked.item.1,
                marker,
            }
        })
        .collect()
}
