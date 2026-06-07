use crate::support::{FakeGh, FakeHook, TestEnv};

#[test]
fn task_open_uses_unique_fuzzy_match() {
    let env = TestEnv::configured();
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");

    let task = env.run_stdout(&["task", "open", "setup"]);
    assert_eq!(
        task.trim(),
        format!(
            "opening {} with VISUAL {}",
            env.path("api/setup-ci").display(),
            env.task_open_stub.display()
        )
    );

    let human = env.run_stdout(&["task", "open", "setup"]);
    assert_eq!(
        human.trim(),
        format!(
            "opening {} with VISUAL {}",
            env.path("api/setup-ci").display(),
            env.task_open_stub.display()
        )
    );
}

#[test]
fn task_open_uses_branch_tail_when_query_has_git_username_prefix() {
    let env = TestEnv::configured();
    let task_path = env.task("test-crew", "node-20-depre");

    let task = env.run_stdout(&["task", "open", "stephanos/node-20-depre"]);

    assert_eq!(
        task.trim(),
        format!(
            "opening {} with VISUAL {}",
            task_path.display(),
            env.task_open_stub.display()
        )
    );
}

#[test]
fn task_open_rejects_ambiguous_matches() {
    let env = TestEnv::configured();
    env.mkdir("api/setup-ci");
    env.mkdir("web/setup-ci");
    env.mkdir("api/.hatch");
    env.mkdir("web/.hatch");

    let output = env.run_output_allow_failure(&["task", "open", "setup-ci"], None);
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("ambiguous task query"));
    assert!(stderr.contains("Potential matches:"));
    assert!(stderr.contains("api/setup-ci"));
    assert!(stderr.contains("web/setup-ci"));
}

#[test]
fn task_open_ambiguous_error_lists_exact_partial_matches() {
    let env = TestEnv::configured();
    env.mkdir("random/otel-chasm-datablog");
    env.mkdir("random/chasm-otel-events");
    env.mkdir("random/cards-against-developers");
    env.mkdir("test-crew/otel-assert-event");
    env.mkdir("random/.hatch");
    env.mkdir("test-crew/.hatch");

    let output = env.run_output_allow_failure(&["task", "open", "otel"], None);

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("ambiguous task query"));
    assert!(stderr.contains("random/otel-chasm-datablog"));
    assert!(stderr.contains("random/chasm-otel-events"));
    assert!(stderr.contains("test-crew/otel-assert-event"));
    assert!(!stderr.contains("random/cards-against-developers"));
}

#[test]
fn task_open_fails_with_invalid_args() {
    let env = TestEnv::configured();
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");

    let output = env.run_output_allow_failure(&["task", "open", "api", "setup-ci"], None);

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("unknown subcommand")
            || stderr.contains("unrecognized subcommand")
            || stderr.contains("invalid subcommand")
            || stderr.contains("unexpected argument"),
        "{stderr}"
    );
}

#[test]
fn task_open_uses_project_task_open_hook_when_present() {
    let env = TestEnv::configured();
    env.mkdir("api");
    env.mkdir("api/.hatch");
    env.mkdir("api/.hatch/hooks");
    env.mkdir("api/feature");

    let hook_log = env.path(".task-open-hook.log");
    let project_hook_path = env.path("api/.hatch/hooks/task_open.sh");
    env.install_hook(
        env.path(".hatch/hooks/task_open.sh"),
        FakeHook::TaskOpenWorkspaceLog,
    );
    env.install_hook(project_hook_path, FakeHook::TaskOpenProjectLog);
    let output = env.run_output_with_env(
        &["task", "open", "api/feature"],
        None,
        &[
            ("HATCH_TASK_OPEN_LOG", hook_log.display().to_string()),
            (
                "HATCH_TEST_WORKSPACE_ROOT",
                env.workspace.display().to_string(),
            ),
        ],
    );
    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout), "");
    assert_eq!(
        fs_err::read_to_string(&hook_log)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", hook_log.display())),
        "project\n"
    );
}

#[test]
fn task_open_accepts_github_pr_url() {
    let env = TestEnv::configured();
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");

    env.install_gh(FakeGh::PrView);

    let output = env.run_output(
        &["task", "open", "https://github.com/acme/web/pull/123"],
        None,
    );

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        format!(
            "opening {} with VISUAL {}",
            env.path("api/setup-ci").display(),
            env.task_open_stub.display()
        )
    );
}

#[test]
fn task_open_uses_last_branch_segment_from_pr_head_ref() {
    let env = TestEnv::configured();
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");

    env.install_gh(FakeGh::PrView);

    let output = env.run_output(
        &["task", "open", "https://github.com/acme/web/pull/456"],
        None,
    );

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        format!(
            "opening {} with VISUAL {}",
            env.path("api/setup-ci").display(),
            env.task_open_stub.display()
        )
    );
}

#[test]
fn task_open_reports_ambiguous_match_from_pr_branch_tail() {
    let env = TestEnv::configured();
    env.mkdir("api/setup-ci");
    env.mkdir("web/setup-ci");
    env.mkdir("api/.hatch");
    env.mkdir("web/.hatch");

    env.install_gh(FakeGh::PrView);

    let output = env.run_output_allow_failure(
        &["task", "open", "https://github.com/acme/web/pull/123"],
        None,
    );

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("ambiguous task query"));
    assert!(stderr.contains("api/setup-ci"));
    assert!(stderr.contains("web/setup-ci"));
}

#[test]
fn task_open_reports_failed_pr_lookup() {
    let env = TestEnv::configured();
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");

    env.install_gh(FakeGh::PrView);

    let output = env.run_output_allow_failure(
        &["task", "open", "https://github.com/acme/web/pull/999"],
        None,
    );

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("could not find pull request"));
}
