use std::path::Path;
use std::process::Command;

use crate::support::{FakeEditor, FakeGh, FakeGit, TestEnv};

#[test]
fn end_to_end_hook_project_task_delete_flow() {
    let env = TestEnv::empty();
    env.install_git(FakeGit::Clone);
    env.install_gh(FakeGh::Login);
    env.install_editor("editor", FakeEditor::Noop);

    let workspace = env.workspace.display().to_string();
    env.run_output(&["workspace", "new", &workspace], None);
    env.write(
        ".hatch/hooks/task_new.sh",
        "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --task-path)\n      task_path=\"$2\"\n      shift 2\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nprintf '@../AGENTS.md\\n' > \"$task_path/AGENTS.md\"\nprintf '@AGENTS.md\\n' > \"$task_path/CLAUDE.md\"\nhatch repo new acme/web --task-path \"$task_path\" --base-branch main\n",
    );

    let project = env.run_stdout(&["project", "new", "api"]);
    assert_eq!(project.trim(), env.path("api").to_string_lossy());

    let task = env.run_output(&["task", "new", "api", "setup-ci"], None);
    assert!(
        task.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&task.stderr)
    );

    let task_path = env.path("api/setup-ci");
    let repo_path = task_path.join("web");
    assert!(!task_path.join("hatch.task.toml").exists());
    assert_eq!(
        fs_err::read_to_string(repo_path.join(".clone_url"))
            .unwrap_or_else(|error| panic!("failed to read clone url: {error}")),
        "https://github.com/acme/web.git\n"
    );
    assert_eq!(
        fs_err::read_to_string(repo_path.join(".branch"))
            .unwrap_or_else(|error| panic!("failed to read branch marker: {error}")),
        "octocat/setup-ci\n"
    );
    assert_eq!(
        fs_err::read_to_string(repo_path.join("AGENTS.override.md"))
            .unwrap_or_else(|error| panic!("failed to read AGENTS.override.md: {error}")),
        "@../AGENTS.md\n"
    );
    let task_open_target = fs_err::read_to_string(&env.task_open_log)
        .unwrap_or_else(|error| panic!("failed to read task open log: {error}"));
    assert_eq!(
        task_open_target.trim_end(),
        task_path.to_string_lossy().to_string()
    );
    assert_eq!(
        fs_err::read_to_string(task_path.join("AGENTS.md"))
            .unwrap_or_else(|error| panic!("failed to read task AGENTS.md: {error}")),
        "@../AGENTS.md\n"
    );
    assert_eq!(
        fs_err::read_to_string(task_path.join("CLAUDE.md"))
            .unwrap_or_else(|error| panic!("failed to read task CLAUDE.md: {error}")),
        "@AGENTS.md\n"
    );

    let tasks = env.run_stdout(&["task", "list"]);
    assert_eq!(tasks.trim(), "api/setup-ci");

    let deleted = env.run_stdout(&["task", "delete", "setup"]);
    assert_eq!(deleted.trim(), env.path("api/setup-ci").to_string_lossy());
    assert!(!task_path.exists());
}

#[test]
fn task_new_checks_out_local_git_repo_without_network() {
    let env = TestEnv::empty();
    env.remove_tool("git");
    env.install_gh(FakeGh::Login);
    let remote = create_local_bare_repo(&env);

    let workspace = env.workspace.display().to_string();
    env.run_output(&["workspace", "new", &workspace], None);
    env.write(
        ".hatch/hooks/task_new.sh",
        format!(
            "#!/usr/bin/env sh\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    --task-path)\n      task_path=\"$2\"\n      shift 2\n      ;;\n    *)\n      shift\n      ;;\n  esac\ndone\nprintf '@../AGENTS.md\\n' > \"$task_path/AGENTS.md\"\nprintf '@AGENTS.md\\n' > \"$task_path/CLAUDE.md\"\nhatch repo new \"file://{}\" --task-path \"$task_path\" --base-branch main\n",
            remote.display()
        ),
    );

    let path = env.path_env();
    env.run_output_with_env(&["project", "new", "api"], None, &[("PATH", path.clone())]);
    let output =
        env.run_output_with_env(&["task", "new", "api", "setup-ci"], None, &[("PATH", path)]);

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let repo_path = env.path("api/setup-ci/fixture");
    assert_eq!(
        fs_err::read_to_string(repo_path.join("README.md"))
            .unwrap_or_else(|error| panic!("failed to read fixture README: {error}")),
        "fixture repo\n"
    );
    assert_eq!(
        git_stdout(["-C", path_arg(&repo_path), "branch", "--show-current"]).trim(),
        "octocat/setup-ci"
    );
    assert_eq!(
        git_stdout([
            "-C",
            path_arg(&repo_path),
            "config",
            "--get",
            "branch.octocat/setup-ci.remote"
        ])
        .trim(),
        "origin"
    );
    assert_eq!(
        git_stdout([
            "-C",
            path_arg(&repo_path),
            "config",
            "--get",
            "branch.octocat/setup-ci.merge"
        ])
        .trim(),
        "refs/heads/octocat/setup-ci"
    );
    assert!(env.path(".hatch/repos").read_dir().is_ok());
}

#[test]
fn task_new_default_repos_checks_out_local_git_repo_without_network() {
    let env = TestEnv::empty();
    env.remove_tool("git");
    env.install_gh(FakeGh::Login);
    let remote = create_local_bare_repo(&env);

    let workspace = env.workspace.display().to_string();
    env.run_output(&["workspace", "new", &workspace], None);
    env.write(
        ".hatch/default-repos.txt",
        format!("file://{} main\n", remote.display()),
    );

    env.run_output(&["project", "new", "api"], None);
    let output = env.run_output(&["task", "new", "api", "setup-ci"], None);

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let repo_path = env.path("api/setup-ci/fixture");
    assert_eq!(
        fs_err::read_to_string(repo_path.join("README.md"))
            .unwrap_or_else(|error| panic!("failed to read fixture README: {error}")),
        "fixture repo\n"
    );
    assert!(repo_path.join(".git").is_dir());
    assert_eq!(
        git_stdout(["-C", path_arg(&repo_path), "branch", "--show-current"]).trim(),
        "octocat/setup-ci"
    );
    assert_eq!(
        git_stdout([
            "-C",
            path_arg(&repo_path),
            "config",
            "--get",
            "branch.octocat/setup-ci.remote"
        ])
        .trim(),
        "origin"
    );
    assert_eq!(
        git_stdout([
            "-C",
            path_arg(&repo_path),
            "config",
            "--get",
            "branch.octocat/setup-ci.merge"
        ])
        .trim(),
        "refs/heads/octocat/setup-ci"
    );
}

fn create_local_bare_repo(env: &TestEnv) -> std::path::PathBuf {
    let work = env.path(".fixture-source-work");
    let bare = env.path(".fixture-remotes/fixture.git");
    fs_err::create_dir_all(bare.parent().expect("bare repo has a parent"))
        .unwrap_or_else(|error| panic!("failed to create bare repo parent: {error}"));
    git_ok([
        "init",
        "--bare",
        "--initial-branch",
        "main",
        path_arg(&bare),
    ]);
    git_ok(["init", "--initial-branch", "main", path_arg(&work)]);
    fs_err::write(work.join("README.md"), "fixture repo\n")
        .unwrap_or_else(|error| panic!("failed to write fixture README: {error}"));
    git_ok(["-C", path_arg(&work), "add", "README.md"]);
    git_ok([
        "-C",
        path_arg(&work),
        "-c",
        "user.name=Hatch Test",
        "-c",
        "user.email=hatch@example.com",
        "commit",
        "-m",
        "init",
    ]);
    git_ok([
        "-C",
        path_arg(&work),
        "remote",
        "add",
        "origin",
        path_arg(&bare),
    ]);
    git_ok(["-C", path_arg(&work), "push", "origin", "main"]);
    bare
}

fn git_ok<const N: usize>(args: [&str; N]) {
    let output = Command::new("git")
        .args(args)
        .output()
        .unwrap_or_else(|error| panic!("failed to run git: {error}"));
    assert!(
        output.status.success(),
        "git failed\nstdout: {}\nstderr: {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn path_arg(path: &Path) -> &str {
    path.to_str()
        .unwrap_or_else(|| panic!("path must be UTF-8: {}", path.display()))
}

fn git_stdout<const N: usize>(args: [&str; N]) -> String {
    let output = Command::new("git")
        .args(args)
        .output()
        .unwrap_or_else(|error| panic!("failed to run git: {error}"));
    assert!(
        output.status.success(),
        "git failed\nstdout: {}\nstderr: {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout)
        .unwrap_or_else(|error| panic!("git stdout was not valid UTF-8: {error}"))
}
