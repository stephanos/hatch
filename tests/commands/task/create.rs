use crate::support::{FakeGh, FakeGit, TestEnv};

#[test]
fn task_new_prints_opening_guidance() {
    let env = TestEnv::configured();
    env.mkdir("p1/.hatch");

    let output = env.run_output(&["task", "new", "p1", "t1"], None);
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert_eq!(
        stdout.trim(),
        format!(
            "opening {} with VISUAL {}",
            env.path("p1/t1").display(),
            env.task_open_stub.display()
        )
    );
    assert!(stderr.contains("\x1b[3m\x1b[90mrunning hook:\x1b[0m"));
    assert!(stderr.contains(".hatch/hooks/task_new.sh"));
    assert!(stderr.contains(".hatch/hooks/task_open.sh"));
}

#[test]
fn task_new_opening_output_comes_from_task_open_hook() {
    let env = TestEnv::configured();
    env.mkdir("p1/.hatch/hooks");
    env.write(
        "p1/.hatch/hooks/task_open.sh",
        "#!/usr/bin/env sh\nprintf 'custom task open hook\\n'\nprintf 'custom task open stderr\\n' >&2\n",
    );

    let output = env.run_output(&["task", "new", "p1", "t2"], None);

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        "custom task open hook"
    );
    assert!(String::from_utf8_lossy(&output.stderr).contains("custom task open stderr"));
}

#[test]
fn task_new_non_interactive_does_not_open_editor() {
    let env = TestEnv::configured();
    env.mkdir("p1/.hatch");

    let output = env.run_output_with_env(
        &["task", "new", "p1", "t3"],
        None,
        &[("HATCH_NON_INTERACTIVE", "1".to_string())],
    );

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        format!(
            "would open {} with default editor",
            env.path("p1/t3").display()
        )
    );
    assert!(!env.task_open_log.exists());
}

#[test]
fn task_new_checks_out_default_repos() {
    let env = TestEnv::configured();
    env.install_git(FakeGit::Clone);
    env.install_gh(FakeGh::Login);
    env.mkdir("p1/.hatch");
    env.write(
        ".hatch/default-repos.txt",
        "acme/web main\n# skipped/comment\n",
    );

    let output = env.run_output_without_forced_color(&["task", "new", "p1", "t-default"], None);

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs_err::read_to_string(env.path("p1/t-default/web/.clone_url"))
            .unwrap_or_else(|error| panic!("failed to read clone url: {error}")),
        "https://github.com/acme/web.git\n"
    );
    assert_eq!(
        fs_err::read_to_string(env.path("p1/t-default/web/.branch"))
            .unwrap_or_else(|error| panic!("failed to read branch marker: {error}")),
        "octocat/t-default\n"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains(&format!(
            "\x1b[3m\x1b[90mrunning hook:\x1b[0m {}",
            env.path(".hatch/hooks/repo_new.sh").display()
        )),
        "{stderr}"
    );
}

#[test]
fn task_new_uses_project_default_repos_when_non_empty() {
    let env = TestEnv::configured();
    env.install_git(FakeGit::Clone);
    env.install_gh(FakeGh::Login);
    env.mkdir("p1/.hatch");
    env.write(".hatch/default-repos.txt", "acme/workspace main\n");
    env.write("p1/.hatch/default-repos.txt", "acme/project main\n");

    let output = env.run_output(&["task", "new", "p1", "t-project"], None);

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(env.path("p1/t-project/project/.clone_url").exists());
    assert!(!env.path("p1/t-project/workspace").exists());
}

#[test]
fn task_new_uses_workspace_default_repos_when_project_file_has_no_entries() {
    let env = TestEnv::configured();
    env.install_git(FakeGit::Clone);
    env.install_gh(FakeGh::Login);
    env.mkdir("p1/.hatch");
    env.write(".hatch/default-repos.txt", "acme/workspace main\n");
    env.write(
        "p1/.hatch/default-repos.txt",
        "# project defaults are intentionally empty\n",
    );

    let output = env.run_output(&["task", "new", "p1", "t-workspace"], None);

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(env.path("p1/t-workspace/workspace/.clone_url").exists());
}

#[test]
fn task_new_opens_existing_hatch_task() {
    let env = TestEnv::configured();
    env.mkdir("p1/.hatch");
    env.mkdir("p1/t1");

    let output = env.run_output(&["task", "new", "p1", "t1"], None);

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        format!(
            "opening {} with VISUAL {}",
            env.path("p1/t1").display(),
            env.task_open_stub.display()
        )
    );
}

#[test]
fn task_new_still_fails_for_existing_non_directory_path() {
    let env = TestEnv::configured();
    env.mkdir("p1/.hatch");
    env.write("p1/t1", "not a directory");

    let output = env.run_output_allow_failure(&["task", "new", "p1", "t1"], None);

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("does not exist"));
}
