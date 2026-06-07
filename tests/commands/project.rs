use crate::support::{FakeGh, TestEnv};

#[test]
fn project_list_prints_projects() {
    let env = TestEnv::configured();
    env.mkdir("api");
    env.mkdir("api/.hatch");

    let projects = env.run_stdout(&["project", "list"]);
    assert_eq!(projects.trim(), "api");
}

#[test]
fn project_new_mutates_workspace() {
    let env = TestEnv::configured();

    let output = env.run_output(&["project", "new", "api"], None);
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        env.path("api").to_string_lossy()
    );
    assert!(
        !String::from_utf8_lossy(&output.stderr).contains("api/.hatch/hooks/project_new.sh"),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(!env.path("api/.project").exists());
    assert!(env.path("api/.hatch").exists());
    assert_eq!(env.read("api/AGENTS.md"), "@../AGENTS.md\n");
    assert_eq!(env.read("api/CLAUDE.md"), "@AGENTS.md\n");
    assert!(
        env.read("api/.hatch/default-repos.txt")
            .contains("owner/repo")
    );
    assert!(env.path("api/.hatch/hooks/project_new.sh").exists());
    assert!(env.path("api/.hatch/hooks/task_new.sh").exists());
    assert!(env.path("api/.hatch/hooks/task_open.sh").exists());
    assert!(env.path("api/.hatch/hooks/repo_new.sh").exists());
    assert!(env.path("api/.hatch/hooks/repo_delete.sh").exists());
    let project_hook = env.read("api/.hatch/hooks/task_new.sh");
    assert!(project_hook.contains("hook workspace task_new"));
}

#[test]
fn project_new_refuses_existing_project_without_force() {
    let env = TestEnv::configured();
    env.mkdir("api/.hatch");
    env.write("api/.hatch/stale.txt", "stale");

    let output = env.run_output_allow_failure(&["project", "new", "api"], None);

    assert!(!output.status.success());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("already exists"),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(env.path("api/.hatch/stale.txt").exists());
}

#[test]
fn project_new_force_replaces_existing_project_hatch_directory() {
    let env = TestEnv::configured();
    env.mkdir("api/.hatch/hooks");
    env.write("api/.hatch/stale.txt", "stale");
    env.write("api/README.md", "keep");

    let project = env.run_stdout(&["project", "new", "--force", "api"]);

    assert_eq!(project.trim(), env.path("api").to_string_lossy());
    assert!(!env.path("api/.hatch/stale.txt").exists());
    assert_eq!(env.read("api/README.md"), "keep");
    assert!(env.path("api/.hatch/hooks/task_new.sh").exists());
}

#[test]
fn project_clean_only_considers_requested_project() {
    let env = TestEnv::configured();
    let web_task = env.path("web/done");
    let web_repo = web_task.join("frontend");
    env.mkdir("web/done/frontend");
    env.mkdir("api/.hatch");
    env.mkdir("web/.hatch");
    assert!(
        std::process::Command::new("git")
            .arg("init")
            .arg(&web_repo)
            .status()
            .unwrap_or_else(|error| panic!(
                "failed to run git init {}: {error}",
                web_repo.display()
            ))
            .success()
    );
    env.install_gh(FakeGh::ClosedPrs);
    env.remove_tool("git");

    let output = env.run_output(&["project", "clean", "api"], None);

    assert!(output.status.success());
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        "No cleanup candidates"
    );
    assert!(web_task.exists());
}

#[test]
fn project_delete_removes_empty_project_without_confirmation() {
    let env = TestEnv::configured();
    env.mkdir("api/.hatch");

    let output = env.run_output(&["project", "delete", "api"], None);

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        env.path("api").display().to_string()
    );
    assert!(!env.path("api").exists());
    assert!(!String::from_utf8_lossy(&output.stderr).contains("Delete project"));
}

#[test]
fn project_delete_lists_tasks_and_keeps_project_when_declined() {
    let env = TestEnv::configured();
    env.mkdir("api/.hatch");
    env.mkdir("api/task-one");
    env.mkdir("api/task-two");

    let output = env.run_output(&["project", "delete", "api"], Some("n\n"));

    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("api contains tasks:"), "stderr: {stderr}");
    assert!(stderr.contains("  - api/task-one"), "stderr: {stderr}");
    assert!(stderr.contains("  - api/task-two"), "stderr: {stderr}");
    assert!(
        stderr.contains("Delete project api? [Y/n]"),
        "stderr: {stderr}"
    );
    assert!(
        stderr.contains("Project deletion cancelled"),
        "stderr: {stderr}"
    );
    assert!(env.path("api").exists());
}

#[test]
fn project_delete_lists_tasks_and_removes_project_when_confirmed() {
    let env = TestEnv::configured();
    env.mkdir("api/.hatch");
    env.mkdir("api/task-one");

    let output = env.run_output(&["project", "delete", "api"], Some("y\n"));

    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        env.path("api").display().to_string()
    );
    assert!(String::from_utf8_lossy(&output.stderr).contains("  - api/task-one"));
    assert!(!env.path("api").exists());
}

#[test]
fn project_list_ignores_legacy_project_markers() {
    let env = TestEnv::configured();
    env.mkdir("api");
    env.write("api/.project", "");

    let projects = env.run_stdout(&["project", "list"]);

    assert_eq!(projects.trim(), "");
}
