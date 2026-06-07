use crate::support::TestEnv;

use fs_err as fs;
use std::path::Path;
use std::process::Command;

#[test]
fn completions_emit_shell_scripts() {
    let env = TestEnv::empty();
    let zsh = env.run_stdout(&["completions", "zsh"]);
    assert!(zsh.contains("#compdef hatch"));
    assert!(zsh.contains("hatch __complete"));
    assert!(zsh.contains("hatch __complete --with-markers --current"));

    let bash = env.run_stdout(&["completions", "bash"]);
    assert!(bash.contains("complete -o nosort -o bashdefault -o default -F _hatch hatch"));
    assert!(bash.contains("hatch __complete"));

    let fish = env.run_stdout(&["completions", "fish"]);
    assert!(fish.contains("complete -c hatch"));
    assert!(fish.contains("hatch __complete --with-description"));
    assert!(fish.contains("hatch __complete"));
    assert!(fish.contains("set -l current (math (count $words) - 1)"));

    let powershell = env.run_stdout(&["completions", "powershell"]);
    assert!(powershell.contains("Register-ArgumentCompleter"));

    let carapace = env.run_stdout(&["completions", "carapace"]);
    assert!(carapace.contains("name: hatch"));
    assert!(carapace.contains("$carapace.bridge.Clap([hatch])"));

    let elvish = env.run_output_allow_failure(&["completions", "elvish"], None);
    assert!(
        elvish.status.success() || {
            String::from_utf8(elvish.stderr)
                .unwrap_or_else(|error| panic!("stderr was not valid UTF-8: {error}"))
                .contains("no longer supported")
        }
    );

    assert!(zsh.contains("zmodload -i zsh/complist"));
    assert!(zsh.contains("ZLS_COLORS"));
    assert!(zsh.contains("=>*=1;33"));
    assert!(zsh.contains("=\\\\?*=1;35"));
    assert!(zsh.contains("ma=1;33"));
    assert!(!zsh.contains("$'\\e[1m'"));
    assert!(zsh.contains("display_values+=(\"> $display_value\")"));
    assert!(zsh.contains("compadd -U -Q -d display_values -a suggestions"));
    assert!(zsh.contains("compstate[insert]=menu"));
    assert!(zsh.contains("compstate[list]='list force'"));
    assert!(!zsh.contains("(default)"));
}

#[cfg(unix)]
#[test]
fn completion_zsh_empty_query_keeps_list_only() {
    let env = TestEnv::empty();
    let script = env.run_stdout(&["completions", "zsh"]);
    let Some(output) = run_zsh_completion_function(&script, &["hatch", ""], Some(&env.workspace))
    else {
        return;
    };

    assert!(output.lines().any(|line| line == "INSERT_BEFORE="));
    assert!(output.lines().any(|line| line == "INSERT_AFTER="));
    assert!(output.lines().any(|line| line == "LIST_AFTER=list force"));
}

#[cfg(unix)]
#[test]
fn completion_zsh_unique_top_match_marks_default_choice() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");
    env.task("api", "sunset");

    let script = env.run_stdout(&["completions", "zsh"]);
    let Some(output) = run_zsh_completion_function(
        &script,
        &["hatch", "task", "open", "set"],
        Some(&env.workspace),
    ) else {
        return;
    };

    assert!(
        output
            .lines()
            .any(|line| line == "DISPLAY=> api/[set]up-task"),
        "{output}"
    );
}

#[cfg(unix)]
#[test]
fn completion_zsh_completed_single_match_does_not_show_preview() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");

    let script = env.run_stdout(&["completions", "zsh"]);
    let Some(output) = run_zsh_completion_function(
        &script,
        &["hatch", "task", "open", "api/setup-task"],
        Some(&env.workspace),
    ) else {
        return;
    };

    assert!(
        output.lines().any(|line| line == "INSERT_AFTER="),
        "{output}"
    );
    assert!(
        !output.lines().any(|line| line == "LIST_AFTER=list force"),
        "{output}"
    );
    assert!(
        !output.lines().any(|line| line.starts_with("DISPLAY=")),
        "{output}"
    );
}

#[cfg(unix)]
#[test]
fn completion_zsh_no_matches_keeps_input_and_shows_message() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");

    let script = env.run_stdout(&["completions", "zsh"]);
    let Some(output) = run_zsh_completion_function(
        &script,
        &["hatch", "task", "open", "zzzz"],
        Some(&env.workspace),
    ) else {
        return;
    };

    assert!(
        output.lines().any(|line| line == "INSERT_AFTER="),
        "{output}"
    );
    assert!(
        output.lines().any(|line| line == "LIST_AFTER=list force"),
        "{output}"
    );
    assert!(
        output
            .lines()
            .any(|line| line == "MESSAGE=no matches for zzzz"),
        "{output}"
    );
}

#[cfg(unix)]
#[test]
fn completion_zsh_fuzzy_query_uses_menu_insert() {
    let env = TestEnv::empty();
    let script = env.run_stdout(&["completions", "zsh"]);
    let Some(output) = run_zsh_completion_function(&script, &["hatch", "w"], Some(&env.workspace))
    else {
        return;
    };

    assert!(output.lines().any(|line| line == "INSERT_AFTER=menu"));
    assert!(output.lines().any(|line| line == "LIST_AFTER=list force"));
}

#[cfg(unix)]
#[test]
fn completion_zsh_multiple_matches_only_refreshes_list() {
    let env = TestEnv::configured();
    env.task("random", "otel-chasm-datablog");
    env.task("random", "chasm-otel-events");
    env.task("random", "cards-against-developers");
    env.task("test-crew", "otel-assert-event");

    let script = env.run_stdout(&["completions", "zsh"]);
    let Some(output) = run_zsh_completion_function(
        &script,
        &["hatch", "task", "open", "otel"],
        Some(&env.workspace),
    ) else {
        return;
    };

    assert!(output.lines().any(|line| line == "INSERT_AFTER="));
    assert!(output.lines().any(|line| line == "LIST_AFTER=list force"));
    assert!(
        output
            .lines()
            .any(|line| line == "DISPLAY=? random/[otel]-chasm-datablog")
    );
    assert!(
        output
            .lines()
            .any(|line| line == "DISPLAY=? random/chasm-[otel]-events")
    );
    assert!(
        output
            .lines()
            .any(|line| line == "DISPLAY=random/cards-against-developers")
    );
    assert!(
        output
            .lines()
            .any(|line| line == "DISPLAY=? test-crew/[otel]-assert-event")
    );
}

#[cfg(unix)]
fn run_zsh_completion_function(
    completion_script: &str,
    words: &[&str],
    workspace_root: Option<&Path>,
) -> Option<String> {
    if Command::new("zsh").arg("-c").arg("true").output().is_err() {
        return None;
    }

    let temp =
        tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
    let completion_path = temp.path().join("hatch-completion.zsh");
    let probe_path = temp.path().join("probe.zsh");
    let shim_path = temp.path().join("hatch");
    let binary = env!("CARGO_BIN_EXE_hatch");

    let mut words_expr = String::new();
    for (idx, word) in words.iter().enumerate() {
        if idx > 0 {
            words_expr.push(' ');
        }
        words_expr.push('"');
        for ch in word.chars() {
            match ch {
                '"' => words_expr.push_str("\\\""),
                '\\' => words_expr.push_str("\\\\"),
                '$' => words_expr.push_str("\\$"),
                '`' => words_expr.push_str("\\`"),
                _ => words_expr.push(ch),
            }
        }
        words_expr.push('"');
    }

    fs::write(&completion_path, completion_script).unwrap_or_else(|error| {
        panic!(
            "failed to write completion script {}: {error}",
            completion_path.display()
        )
    });
    fs::write(
        &shim_path,
        include_str!("../fixtures/scripts/hatch-shim.sh").replace("{HATCH_BINARY}", binary),
    )
    .unwrap_or_else(|error| panic!("failed to write shim {}: {error}", shim_path.display()));
    crate::support::make_executable(&shim_path);

    let probe = include_str!("../fixtures/scripts/zsh-completion-probe.zsh")
        .replace("{COMPLETION_PATH}", &completion_path.display().to_string())
        .replace("{WORDS_EXPR}", &words_expr)
        .replace("{CURRENT}", &words.len().to_string());
    fs::write(&probe_path, probe)
        .unwrap_or_else(|error| panic!("failed to write probe {}: {error}", probe_path.display()));

    let mut command = Command::new("zsh");
    command.arg("-f").arg(probe_path).env(
        "PATH",
        format!(
            "{}:{}",
            temp.path().display(),
            std::env::var("PATH").unwrap_or_else(|_| String::from(""))
        ),
    );
    if let Some(workspace_root) = workspace_root {
        command.env("HATCH_TEST_WORKSPACE_ROOT", workspace_root);
    }
    let status = command
        .output()
        .unwrap_or_else(|error| panic!("failed to run zsh completion probe: {error}"));
    if !status.status.success() {
        panic!(
            "zsh completion probe failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&status.stdout),
            String::from_utf8_lossy(&status.stderr)
        );
    }
    Some(String::from_utf8_lossy(&status.stdout).to_string())
}

#[test]
fn completion_suggests_fuzzy_task_matches() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");
    env.task("api", "setup-feature");

    let output = env.run_stdout(&["__complete", "--current", "2", "task", "open", "set"]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"api/setup-feature"));
    assert!(lines.contains(&"api/setup-task"));
}

#[test]
fn carapace_complete_suggests_fuzzy_task_matches() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");
    env.task("api", "setup-feature");

    let output = env.run_stdout(&[
        "complete",
        "--index",
        "3",
        "--type",
        "9",
        "--no-space",
        "--ifs=\n",
        "--",
        "hatch",
        "task",
        "open",
        "set",
    ]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"api/setup-feature"));
    assert!(lines.contains(&"api/setup-task"));
}

#[test]
fn completion_task_matches_do_not_include_path_descriptions() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");

    let output = env.run_stdout(&[
        "__complete",
        "--with-description",
        "--current",
        "2",
        "task",
        "open",
        "set",
    ]);
    let lines: Vec<&str> = output.lines().collect();

    assert_eq!(lines, vec!["api/setup-task"]);
}

#[test]
fn completion_task_matches_ignore_task_paths() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");

    let output = env.run_stdout(&["__complete", "--current", "2", "task", "open", "Workspace"]);

    assert_eq!(output.trim(), "");
}

#[test]
fn completion_normalizes_full_path_command_token() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");

    let output = env.run_stdout(&[
        "__complete",
        "--current",
        "3",
        "/usr/local/bin/hatch",
        "task",
        "open",
        "set",
    ]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"api/setup-task"));
}

#[test]
fn completion_normalizes_when_command_token_is_prefixed() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");

    let output = env.run_stdout(&[
        "__complete",
        "--current",
        "4",
        "env",
        "hatch",
        "task",
        "open",
        "set",
    ]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"api/setup-task"));
}

#[test]
fn completion_shows_task_matches_when_open_is_complete() {
    let env = TestEnv::configured();
    env.task("api", "setup-task");
    env.task("api", "setup-feature");

    let output = env.run_stdout(&["__complete", "--current", "1", "task", "open"]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"api/setup-feature"));
    assert!(lines.contains(&"api/setup-task"));
}

#[test]
fn completion_task_open_empty_query_shows_recently_created_tasks_first() {
    let env = TestEnv::configured();
    env.task("api", "a-old");
    std::thread::sleep(std::time::Duration::from_millis(50));
    env.task("api", "z-new");

    let output = env.run_stdout(&["__complete", "--current", "2", "task", "open", ""]);
    let lines: Vec<&str> = output.lines().collect();

    assert_eq!(lines, vec!["api/z-new", "api/a-old"]);
}

#[test]
fn completion_shows_task_candidates_for_partial_task_query_with_project_prefix() {
    let env = TestEnv::configured();
    env.task("random", "test");
    env.project_marker("random/test");
    env.task("random", "setup-task");
    env.project_marker("random/setup-task");

    let output = env.run_stdout(&[
        "__complete",
        "--current",
        "3",
        "hatch",
        "task",
        "open",
        "random/t",
    ]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"random/test"));
    assert!(lines.contains(&"random/setup-task"));
}

#[test]
fn completion_task_open_does_not_complete_second_argument() {
    let env = TestEnv::configured();
    env.task("random", "test");
    env.task("random", "setup-task");

    let output = env.run_stdout(&[
        "__complete",
        "--current",
        "3",
        "task",
        "open",
        "random/test",
        "",
    ]);

    assert_eq!(output.trim(), "");
}

#[test]
fn completion_task_new_projects_do_not_include_path_descriptions() {
    let env = TestEnv::configured();
    env.project("p1");
    env.project("testproj");

    let output = env.run_stdout(&[
        "__complete",
        "--with-description",
        "--current",
        "2",
        "task",
        "new",
        "",
    ]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"p1"));
    assert!(lines.contains(&"testproj"));
    assert!(!lines.iter().any(|line| line.contains("path: ")));
}

#[test]
fn completion_project_subcommands_with_trailing_empty_token() {
    let env = TestEnv::empty();
    let output = env.run_stdout(&["__complete", "--current", "2", "project", ""]);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.contains(&"list"));
    assert!(lines.contains(&"new"));
    assert!(lines.contains(&"clean"));
    assert!(lines.contains(&"delete"));
    assert!(lines.contains(&"help"));
}

#[test]
fn completion_workspace_new_suggests_directories() {
    let env = TestEnv::empty();
    env.mkdir("alpha");
    env.mkdir("beta");
    env.write("regular-file", "not a directory");

    let output = env.run_output_in_dir(
        &["__complete", "--current", "2", "workspace", "new", ""],
        None,
        &env.workspace,
    );
    let lines = String::from_utf8(output.stdout)
        .unwrap_or_else(|error| panic!("stdout was not valid UTF-8: {error}"));
    let lines: Vec<&str> = lines.lines().collect();

    assert!(lines.contains(&"alpha/"));
    assert!(lines.contains(&"beta/"));
    assert!(!lines.contains(&"regular-file"));
}

#[test]
fn completion_workspace_new_filters_directory_prefix() {
    let env = TestEnv::empty();
    env.mkdir("workspace-one");
    env.mkdir("scratch");

    let output = env.run_output_in_dir(
        &["__complete", "--current", "2", "workspace", "new", "work"],
        None,
        &env.workspace,
    );
    let lines = String::from_utf8(output.stdout)
        .unwrap_or_else(|error| panic!("stdout was not valid UTF-8: {error}"));
    let lines: Vec<&str> = lines.lines().collect();

    assert!(lines.contains(&"workspace-one/"));
    assert!(!lines.contains(&"scratch/"));
}

#[test]
fn completion_workspace_new_suggests_nested_directories() {
    let env = TestEnv::empty();
    env.mkdir("parent/child");
    env.mkdir("parent/other");

    let output = env.run_output_in_dir(
        &[
            "__complete",
            "--current",
            "2",
            "workspace",
            "new",
            "parent/c",
        ],
        None,
        &env.workspace,
    );
    let lines = String::from_utf8(output.stdout)
        .unwrap_or_else(|error| panic!("stdout was not valid UTF-8: {error}"));
    let lines: Vec<&str> = lines.lines().collect();

    assert!(lines.contains(&"parent/child/"));
    assert!(!lines.contains(&"parent/other/"));
}
