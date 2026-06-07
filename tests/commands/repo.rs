use fs_err as fs;

use std::path::Path;

use crate::support::{FakeEditor, FakeGh, FakeGit, TestEnv, make_git_repo_with_origin};

#[test]
fn repo_new_rejects_bare_repo_when_no_org_can_be_inferred() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");

    let output = env.run_output_allow_failure(&["repo", "new", "web", path_arg(&task)], None);

    env.assert_failure_contains(&output, "Could not infer repo namespace");
}

#[test]
fn repo_new_rejects_bare_repo_when_task_repos_use_mixed_orgs() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");
    make_git_repo_with_origin(&task.join("backend"), "https://github.com/acme/backend.git");
    make_git_repo_with_origin(&task.join("frontend"), "git@github.com:other/frontend.git");

    let output = env.run_output_allow_failure(&["repo", "new", "web", path_arg(&task)], None);

    env.assert_failure_contains(&output, "multiple GitHub namespaces");
}

#[test]
fn repo_new_adds_repo_from_top_level_command() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir(".hatch");
    env.mkdir("api/.hatch");
    env.install_git(FakeGit::Clone);

    let output = env.run_output(&["repo", "new", "acme/web", path_arg(&task)], None);

    env.assert_success(&output);
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "");
    assert_eq!(
        env.read("api/setup-ci/web/.clone_url"),
        "https://github.com/acme/web.git\n"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains(".hatch/hooks/repo_new.sh"));
    assert!(stderr.contains("cloning https://github.com/acme/web.git"));
}

#[test]
fn repo_new_clones_from_cache_instead_of_copying_git_directory() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    let git_log = env.path("git.log");
    env.mkdir("api/setup-ci");
    env.mkdir(".hatch");
    env.mkdir("api/.hatch");
    env.install_git(FakeGit::Clone);

    let output = env.run_output_with_env(
        &["repo", "new", "acme/web", path_arg(&task)],
        None,
        &[("HATCH_GIT_LOG", git_log.to_string_lossy().to_string())],
    );

    env.assert_success(&output);
    let log = fs::read_to_string(&git_log)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", git_log.display()));
    let repo_path = fs::canonicalize(task.join("web"))
        .unwrap_or_else(|error| panic!("failed to canonicalize repo path: {error}"));
    assert!(
        log.lines().any(|line| {
            line.starts_with("clone ")
                && line.contains("/.hatch/repos/https___github.com_acme_web.git_ ")
                && line.ends_with(&repo_path.display().to_string())
        }),
        "{log}"
    );
    assert!(log.contains(&format!(
        "-C {} remote set-url origin https://github.com/acme/web.git",
        repo_path.display()
    )));
}

#[test]
fn repo_new_uses_explicit_checkout_directory_name() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir(".hatch");
    env.mkdir("api/.hatch");
    env.install_git(FakeGit::Clone);

    let output = env.run_output(
        &[
            "repo",
            "new",
            "acme/web",
            path_arg(&task),
            "--dir",
            "frontend",
        ],
        None,
    );

    env.assert_success(&output);
    assert_eq!(
        env.read("api/setup-ci/frontend/.clone_url"),
        "https://github.com/acme/web.git\n"
    );
    assert!(!env.path("api/setup-ci/web").exists());
}

#[test]
fn repo_new_help_shows_dir_flag() {
    let env = TestEnv::configured();

    let output = env.run_output(&["repo", "new", "--help"], None);
    let stdout = String::from_utf8_lossy(&output.stdout);

    assert!(stdout.contains("--dir <CHECKOUT_DIR>"));
    assert!(!stdout.contains("--checkout-dir"));
}

#[test]
fn repo_new_unknown_flag_shows_full_help_without_positional_tip() {
    let env = TestEnv::configured();

    let output = env.run_output_allow_failure(&["repo", "new", "acme/web", "--wat"], None);
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert!(stderr.contains("unexpected argument '--wat'"));
    assert!(stderr.contains("Usage: hatch repo new [OPTIONS] <REPO> [TASK_PATH]"));
    assert!(stderr.contains("--task-path <TASK_PATH_FLAG>"));
    assert!(stderr.contains("--base-branch <BASE_BRANCH>"));
    assert!(stderr.contains("--dir <CHECKOUT_DIR>"));
    assert!(!stderr.contains("to pass '--wat' as a value"));
    assert!(!stderr.contains("For more information, try '--help'."));
}

#[test]
fn repo_new_existing_checkout_directory_error_uses_explicit_name() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci/frontend");
    env.mkdir("api/.hatch");
    env.install_git(FakeGit::Clone);

    let output = env.run_output_allow_failure(
        &[
            "repo",
            "new",
            "acme/web",
            path_arg(&task),
            "--dir",
            "frontend",
        ],
        None,
    );

    env.assert_failure_contains(&output, "repo checkout directory 'frontend'");
    env.assert_failure_contains(&output, &task.join("frontend").display().to_string());
}

#[test]
fn repo_new_rejects_invalid_checkout_directory_name() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");
    env.install_git(FakeGit::Clone);

    let output = env.run_output_allow_failure(
        &[
            "repo",
            "new",
            "acme/web",
            path_arg(&task),
            "--dir",
            "../web",
        ],
        None,
    );

    env.assert_failure_contains(&output, "checkout directory name must match");
}

#[test]
fn repo_new_from_task_directory_uses_project_hook_templates() {
    let env = TestEnv::empty();
    env.install_git(FakeGit::Clone);
    let workspace = env.workspace.display().to_string();
    env.run_output(&["workspace", "new", &workspace], None);
    env.run_output(&["project", "new", "api"], None);
    env.mkdir("api/setup-ci");
    let task = env.path("api/setup-ci");

    let output =
        env.run_output_discovering_workspace_in_dir(&["repo", "new", "acme/web"], None, &task);

    env.assert_success(&output);
    assert_eq!(
        env.read("api/setup-ci/web/.clone_url"),
        "https://github.com/acme/web.git\n"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("api/.hatch/hooks/repo_new.sh"));
    assert!(stderr.contains("Workspace/.hatch/hooks/repo_new.sh"));
}

#[test]
fn repo_new_existing_checkout_directory_error_names_destination() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci/web");
    env.mkdir("api/.hatch");
    env.install_git(FakeGit::Clone);

    let output = env.run_output_allow_failure(&["repo", "new", "acme/web", path_arg(&task)], None);

    env.assert_failure_contains(&output, "repo checkout directory 'web'");
    env.assert_failure_contains(&output, &task.join("web").display().to_string());
}

#[test]
fn repo_new_prints_hook_path_when_hook_fails() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");
    env.write(
        ".hatch/hooks/repo_new.sh",
        "#!/usr/bin/env sh\nprintf 'boom\\n' >&2\nexit 1\n",
    );

    let output = env.run_output_allow_failure(&["repo", "new", "acme/web", path_arg(&task)], None);

    env.assert_failure_contains(&output, ".hatch/hooks/repo_new.sh");
    env.assert_failure_contains(&output, "boom");
}

#[test]
fn repo_new_includes_parent_and_repo_agents_in_override_if_repo_agents_exist() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir(".hatch");
    env.mkdir("api/.hatch");

    env.install_git(FakeGit::CloneWithAgents);

    let output = env.run_output(&["repo", "new", "acme/web", path_arg(&task)], None);

    env.assert_success(&output);
    let repo_path = task.join("web");
    assert_eq!(
        fs::read_to_string(repo_path.join("AGENTS.override.md")).unwrap_or_else(|error| {
            panic!(
                "failed to read {}: {error}",
                repo_path.join("AGENTS.override.md").display()
            )
        }),
        "@../AGENTS.md\n@AGENTS.md\n## Repo Instructions\n"
    );
    assert_eq!(
        fs::read_to_string(repo_path.join("CLAUDE.local.md")).unwrap_or_else(|error| {
            panic!(
                "failed to read {}: {error}",
                repo_path.join("CLAUDE.local.md").display()
            )
        }),
        "@AGENTS.override.md\n"
    );
}

#[test]
fn repo_new_infers_org_from_existing_task_repos() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");
    env.mkdir("api/setup-ci/backend/.git");
    env.write(
        "api/setup-ci/backend/.origin",
        "https://github.com/acme/backend.git",
    );
    env.mkdir("api/setup-ci/frontend/.git");
    env.write(
        "api/setup-ci/frontend/.origin",
        "git@github.com:acme/frontend.git",
    );
    env.install_git(FakeGit::Clone);
    env.install_gh(FakeGh::Login);

    let output = env.run_output(&["repo", "new", "web", path_arg(&task)], None);

    env.assert_success(&output);
    assert_eq!(
        env.read("api/setup-ci/web/.clone_url"),
        "https://github.com/acme/web.git\n"
    );
}

#[test]
fn repo_new_rejects_gitlab_namespace_from_existing_task_repos() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");
    env.mkdir("api/setup-ci/backend/.git");
    env.write(
        "api/setup-ci/backend/.origin",
        "https://gitlab.com/acme/platform/backend.git",
    );
    env.mkdir("api/setup-ci/frontend/.git");
    env.write(
        "api/setup-ci/frontend/.origin",
        "git@gitlab.com:acme/platform/frontend.git",
    );
    env.install_git(FakeGit::Clone);
    env.install_gh(FakeGh::Login);
    env.install_editor("editor", FakeEditor::Noop);

    let output = env.run_output_allow_failure(&["repo", "new", "web", path_arg(&task)], None);

    env.assert_failure_contains(&output, "Task repos include non-GitHub URLs");
}

fn path_arg(path: &Path) -> &str {
    path.to_str()
        .unwrap_or_else(|| panic!("path must be UTF-8: {}", path.display()))
}
