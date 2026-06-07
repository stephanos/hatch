use crate::support::{TestEnv, make_executable};
use fs_err as fs;

#[test]
fn agent_start_runs_hook_with_task_scope_from_task_directory() {
    let env = TestEnv::configured();
    let task = env.task("api", "setup-ci");
    env.write(
        ".hatch/hooks/agent_start.sh",
        "#!/usr/bin/env sh\nagent=\"\"\nscope=\"\"\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --agent)\n      agent=\"$2\"\n      shift 2\n      ;;\n    --scope-path)\n      scope=\"$2\"\n      shift 2\n      ;;\n    --)\n      shift\n      break\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nprintf 'agent=%s\\nscope=%s\\nargs=%s\\n' \"$agent\" \"$scope\" \"$*\"\n",
    );

    let output = env.run_output_in_dir(
        &["agent", "start", "codex", "--", "--model", "gpt-5.3"],
        None,
        &task,
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    let task = fs::canonicalize(task)
        .unwrap_or_else(|error| panic!("failed to canonicalize task path: {error}"));
    assert!(stdout.contains("agent=codex"));
    assert!(stdout.contains(&format!("scope={}", task.display())));
    assert!(stdout.contains("args=--model gpt-5.3"));
}

#[test]
fn agent_start_runs_hook_with_project_scope_from_project_directory() {
    let env = TestEnv::configured();
    let project = env.project("api");
    env.write(
        ".hatch/hooks/agent_start.sh",
        "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --scope-path)\n      printf '%s\\n' \"$2\"\n      exit 0\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nexit 1\n",
    );

    let output = env.run_output_in_dir(&["agent", "start", "claude"], None, &project);

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        fs::canonicalize(project)
            .unwrap_or_else(|error| panic!("failed to canonicalize project path: {error}"))
            .display()
            .to_string()
    );
}

#[test]
fn agent_start_uses_project_hook_when_available() {
    let env = TestEnv::configured();
    let task = env.task("api", "setup-ci");
    env.mkdir("api/.hatch/hooks");
    env.write(
        ".hatch/hooks/agent_start.sh",
        "#!/usr/bin/env sh\nprintf 'workspace\\n'\n",
    );
    env.write(
        "api/.hatch/hooks/agent_start.sh",
        "#!/usr/bin/env sh\nprintf 'project\\n'\n",
    );

    let output = env.run_output_in_dir(&["agent", "start", "codex"], None, &task);

    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "project");
}

#[test]
fn agent_start_runs_hook_with_workspace_scope_from_workspace_directory() {
    let env = TestEnv::configured();
    env.write(
        ".hatch/hooks/agent_start.sh",
        "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --scope-path)\n      printf '%s\\n' \"$2\"\n      exit 0\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nexit 1\n",
    );

    let output = env.run_output_in_dir(&["agent", "start", "custom-agent"], None, &env.workspace);

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        fs::canonicalize(&env.workspace)
            .unwrap_or_else(|error| panic!("failed to canonicalize workspace path: {error}"))
            .display()
            .to_string()
    );
}

#[test]
fn agent_start_fails_outside_workspace() {
    let env = TestEnv::configured();
    let outside = env.workspace.parent().unwrap();

    let output = env.run_output_in_dir(&["agent", "start", "codex"], None, outside);

    env.assert_failure_contains(&output, "must be run from inside a Hatch workspace");
}

#[test]
fn workspace_new_scaffolds_agent_start_hook() {
    let env = TestEnv::empty();
    let workspace = env.workspace.display().to_string();

    env.run_output(&["workspace", "new", &workspace], None);

    assert!(env.path(".hatch/hooks/agent_start.sh").exists());
}

#[test]
fn default_agent_start_hook_spells_out_sandbox_policy() {
    let env = TestEnv::configured();
    let task = env.task("api", "setup-ci");
    let fake_hatch = env.path(".hatch-test-hatch");
    let log = env.path(".hatch-agent-exec.log");
    fs::write(
        &fake_hatch,
        format!(
            "#!/usr/bin/env sh\n\
if [ \"$1\" = \"workspace\" ] && [ \"$2\" = \"root\" ]; then\n\
  printf '%s\\n' \"$HATCH_TEST_WORKSPACE_ROOT\"\n\
  exit 0\n\
fi\n\
printf '%s\\n' \"$*\" > '{}'\n",
            log.display()
        ),
    )
    .unwrap_or_else(|error| panic!("failed to write fake hatch: {error}"));
    make_executable(&fake_hatch);

    env.run_output_with_extra_env_in_dir(
        &["agent", "start", "codex", "--", "--version"],
        None,
        &[("HATCH_BIN", fake_hatch.display().to_string())],
        &task,
    );

    let command = fs::read_to_string(&log)
        .unwrap_or_else(|error| panic!("failed to read fake hatch log: {error}"));
    let task = fs::canonicalize(task)
        .unwrap_or_else(|error| panic!("failed to canonicalize task path: {error}"));
    assert!(command.contains("__agent-exec codex"));
    assert!(command.contains("--profile always-further/codex"));
    assert!(!command.contains("--profile-cache"));
    assert!(command.contains(&format!("--allow {}", task.display())));
    assert!(command.ends_with("-- --version\n"));
}
