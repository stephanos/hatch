use fs_err as fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Output, Stdio};

use tempfile::TempDir;

mod support;

use support::make_executable;

#[test]
fn pre_push_ignores_non_tag_pushes() {
    let repo = HookRepo::new("0.3.0");

    let output = repo.run_hook("refs/heads/main 111 refs/heads/main 000", None);

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn pre_push_rejects_short_release_tags() {
    let repo = HookRepo::new("0.3.0");
    repo.tag_head("v0.3");

    let output = repo.run_hook("refs/tags/v0.3 111 refs/tags/v0.3 000", None);

    assert!(
        !output.status.success(),
        "stdout: {}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .contains("release tag must use full semver, for example: v0.5.0")
    );
}

#[test]
fn pre_push_rejects_mismatched_cargo_version() {
    let repo = HookRepo::new("0.3.0");
    repo.tag_head("v0.4.0");

    let output = repo.run_hook("refs/tags/v0.4.0 111 refs/tags/v0.4.0 000", None);

    assert!(
        !output.status.success(),
        "stdout: {}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .contains("release tag version (0.4.0) must match Cargo.toml version (0.3.0)")
    );
}

#[test]
fn pre_push_runs_validation_for_matching_release_tags() {
    let repo = HookRepo::new("0.3.0");
    repo.tag_head("v0.3.0");
    let bin_dir = repo.temp.path().join("bin");
    fs::create_dir_all(&bin_dir).unwrap();

    let log_path = repo.temp.path().join("mise.log");
    fs::write(
        bin_dir.join("mise"),
        format!(
            "#!/usr/bin/env sh\nset -eu\nprintf '%s\\n' \"$*\" >> \"{}\"\n",
            log_path.display()
        ),
    )
    .unwrap();
    make_executable(&bin_dir.join("mise"));

    let output = repo.run_hook("refs/tags/v0.3.0 111 refs/tags/v0.3.0 000", Some(&bin_dir));

    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(log_path).unwrap(),
        "run check\nrun test\n"
    );
}

struct HookRepo {
    temp: TempDir,
    root: std::path::PathBuf,
}

impl HookRepo {
    fn new(version: &str) -> Self {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("repo");
        fs::create_dir_all(root.join(".githooks")).unwrap();
        fs::write(
            root.join("Cargo.toml"),
            format!("[package]\nname = \"hatch\"\nversion = \"{version}\"\n"),
        )
        .unwrap();
        fs::write(
            root.join(".githooks/pre-push"),
            include_str!("../.githooks/pre-push"),
        )
        .unwrap();
        make_executable(&root.join(".githooks/pre-push"));

        run(&root, ["git", "init"]);
        run(&root, ["git", "config", "user.name", "Test User"]);
        run(&root, ["git", "config", "user.email", "test@example.com"]);
        run(&root, ["git", "add", "Cargo.toml", ".githooks/pre-push"]);
        run(&root, ["git", "commit", "-m", "init"]);

        Self { temp, root }
    }

    fn tag_head(&self, tag: &str) {
        run(&self.root, ["git", "tag", tag]);
    }

    fn run_hook(&self, input: &str, extra_bin_dir: Option<&Path>) -> Output {
        let mut command = Command::new(self.root.join(".githooks/pre-push"));
        command
            .arg("origin")
            .arg("git@github.com:stephanos/hatch.git")
            .current_dir(&self.root)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        if let Some(extra_bin_dir) = extra_bin_dir {
            let path = std::env::var_os("PATH").unwrap_or_default();
            let mut paths = vec![extra_bin_dir.to_path_buf()];
            paths.extend(std::env::split_paths(&path));
            let joined = std::env::join_paths(paths).unwrap();
            command.env("PATH", joined);
        }

        let mut child = command.spawn().unwrap();
        child
            .stdin
            .as_mut()
            .unwrap()
            .write_all(format!("{input}\n").as_bytes())
            .unwrap();
        child.wait_with_output().unwrap()
    }
}

fn run<const N: usize>(current_dir: &Path, args: [&str; N]) {
    let status = Command::new(args[0])
        .args(&args[1..])
        .current_dir(current_dir)
        .status()
        .unwrap();
    assert!(status.success(), "command failed: {args:?}");
}
