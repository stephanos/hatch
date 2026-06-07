use fs_err as fs;

use crate::support::{FakeGh, TestEnv};

#[test]
fn workspace_new_creates_workspace_and_agents_file() {
    let env = TestEnv::empty();
    let workspace = env.workspace.display().to_string();
    let output = env.run_output(&["workspace", "new", &workspace], None);
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        "Initialized workspace"
    );
    assert_eq!(env.read("AGENTS.md"), "## Workspace Instructions\n");
    assert!(env.read(".hatch/default_repos.txt").contains("owner/repo"));
    assert!(env.path(".hatch/hooks/task_new.sh").exists());
    let config = fs::read_to_string(env.config_file())
        .unwrap_or_else(|error| panic!("failed to read hatch config: {error}"));
    assert!(config.contains(&format!("workspace_root = \"{}\"", env.workspace.display())));
}

#[test]
fn workspace_root_prints_configured_workspace_root() {
    let env = TestEnv::empty();
    let workspace = env.workspace.display().to_string();
    env.run_output(&["workspace", "new", &workspace], None);

    let output = env.run_output_discovering_workspace_in_dir(
        &["workspace", "root"],
        None,
        env.workspace.parent().unwrap(),
    );

    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), workspace);
}

#[test]
fn workspace_aware_commands_refresh_default_hook_copies() {
    let env = TestEnv::configured();
    assert!(!env.path(".hatch/hooks/task_open.default.sh").exists());

    env.run_output(&["workspace", "root"], None);

    let data = env.read(".hatch/hooks/task_open.default.sh");
    assert!(data.starts_with("# This is Hatch's bundled default hook for task_open.\n"));
    assert!(data.ends_with(include_str!("../../templates/hooks/task_open.sh")));
}

#[test]
fn workspace_new_refuses_existing_workspace_without_force() {
    let env = TestEnv::empty();
    let workspace = env.workspace.display().to_string();
    env.run_output(&["workspace", "new", &workspace], None);

    let output = env.run_output_allow_failure(&["workspace", "new", &workspace], None);
    assert!(!output.status.success());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("pass --force"),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn workspace_new_force_recreates_hatch_directory() {
    let env = TestEnv::empty();
    let workspace = env.workspace.display().to_string();
    env.run_output(&["workspace", "new", &workspace], None);

    env.write(".hatch/custom", "keep");
    assert!(env.path(".hatch/custom").exists());

    let output = env.run_output(&["workspace", "new", &workspace, "--force"], None);
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("Initialized workspace"));
    assert!(!env.path(".hatch/custom").exists());
    assert!(env.path(".hatch/hooks/repo_new.sh").exists());
}

#[test]
fn workspace_new_does_not_overwrite_existing_workspace_agents() {
    let env = TestEnv::empty();
    env.mkdir("");
    env.write("AGENTS.md", "kept manual value\n");

    let workspace = env.workspace.display().to_string();
    let output = env.run_output(&["workspace", "new", &workspace], None);
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(env.read("AGENTS.md"), "kept manual value\n");
}

#[test]
fn workspace_new_accepts_current_directory() {
    let env = TestEnv::empty();
    fs::create_dir_all(&env.workspace).unwrap_or_else(|error| {
        panic!(
            "failed to create workspace {}: {error}",
            env.workspace.display()
        )
    });

    let output = env.run_output_in_dir(&["workspace", "new", "."], None, &env.workspace);

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(env.path(".hatch/hooks/task_new.sh").exists());
}

#[test]
fn workspace_hook_runs_workspace_hook_with_forwarded_args() {
    let env = TestEnv::configured();
    env.write(
        ".hatch/hooks/task_open.sh",
        "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --task-path)\n      printf 'workspace hook saw %s\\n' \"$2\"\n      exit 0\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nexit 1\n",
    );

    let output = env.run_output(
        &["hook", "workspace", "task_open", "--task-path", "api/task"],
        None,
    );

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        "workspace hook saw api/task"
    );
    assert!(String::from_utf8_lossy(&output.stderr).contains(".hatch/hooks/task_open.sh"));
}

#[test]
fn workspace_hook_uses_configured_workspace_root_from_project_directory() {
    let env = TestEnv::configured();
    env.write(
        ".hatch/hooks/project_new.sh",
        "#!/usr/bin/env sh\nprintf 'workspace project hook\\n'\n",
    );
    env.write(
        "api/.hatch/hooks/project_new.sh",
        "#!/usr/bin/env sh\nprintf 'project wrapper should not run\\n'\nexit 1\n",
    );
    env.write("api/.hatch/hooks/lib/hatch.sh", "");

    let output = env.run_output_discovering_workspace_in_dir(
        &["hook", "workspace", "project_new"],
        None,
        &env.path("api"),
    );

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        "workspace project hook"
    );
    assert!(String::from_utf8_lossy(&output.stderr).contains(".hatch/hooks/project_new.sh"));
}

#[test]
fn workspace_clean_lists_and_removes_candidates() {
    let env = TestEnv::configured();
    let task = env.path("api/done");
    let repo = task.join("web");
    fs::create_dir_all(&repo)
        .unwrap_or_else(|error| panic!("failed to create {}: {error}", repo.display()));
    env.mkdir("api/.hatch");
    env.install_gh(FakeGh::ClosedPrs);
    env.remove_tool("git");

    assert!(
        std::process::Command::new("git")
            .arg("init")
            .arg("--initial-branch")
            .arg("done")
            .arg(&repo)
            .status()
            .unwrap_or_else(|error| panic!("failed to run git init {}: {error}", repo.display()))
            .success()
    );

    let output = env.run_output(&["workspace", "clean"], None);
    let dry_run = String::from_utf8(output.stdout)
        .unwrap_or_else(|error| panic!("stdout was not valid UTF-8: {error}"));
    assert!(dry_run.contains("No tasks selected for cleanup"));
    assert!(String::from_utf8_lossy(&output.stderr).contains(".hatch/hooks/repo_delete.sh"));
    assert!(task.exists());
}
