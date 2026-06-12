use crate::support::fake_editor::{self, FakeEditor};
use crate::support::fake_gh::{self, FakeGh};
use crate::support::fake_git::{self, FakeGit};
use crate::support::fake_hook::{self, FakeHook};
use crate::support::scripts::make_executable;
use assert_cmd::Command;
use fs_err as fs;
use std::path::Path;
use std::path::PathBuf;
use std::process::Output;

pub struct TestEnv {
    _temp: tempfile::TempDir,
    pub workspace: std::path::PathBuf,
    test_bin: std::path::PathBuf,
    config_file: std::path::PathBuf,
    pub task_open_stub: std::path::PathBuf,
    pub task_open_log: std::path::PathBuf,
}

impl TestEnv {
    pub fn empty() -> Self {
        let temp =
            tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let workspace = temp.path().join("Workspace");
        let test_bin = temp.path().join(".hatch-test-bin");
        let config_file = temp.path().join(".hatch-config.toml");
        let task_open_stub = temp.path().join(".hatch-task-open-stub");
        let task_open_log = temp.path().join(".hatch-task-open.log");
        fs::create_dir_all(&test_bin).unwrap_or_else(|error| {
            panic!("failed to create bin dir {}: {error}", test_bin.display())
        });
        let git = test_bin.join("git");
        write_executable(&git, fake_git::script(FakeGit::Default));
        let gh = test_bin.join("gh");
        write_executable(&gh, fake_gh::script(FakeGh::Default));
        write_executable(&task_open_stub, TASK_OPEN_STUB);
        Self {
            _temp: temp,
            workspace,
            test_bin,
            config_file,
            task_open_stub,
            task_open_log,
        }
    }

    pub fn configured() -> Self {
        let env = Self::empty();
        env.mkdir(".hatch/lib");
        env.mkdir(".hatch/hooks");
        fs::write(
            env.workspace.join(".hatch/lib/hatch.sh"),
            include_str!("../../templates/lib/hatch.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write hatch hook lib: {error}"));
        fs::write(
            env.workspace.join(".hatch/lib/args.sh"),
            include_str!("../../templates/lib/args.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write args hook lib: {error}"));
        fs::write(
            env.workspace.join(".hatch/lib/path.sh"),
            include_str!("../../templates/lib/path.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write path hook lib: {error}"));
        fs::write(
            env.workspace.join(".hatch/lib/repo.sh"),
            include_str!("../../templates/lib/repo.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write repo hook lib: {error}"));
        fs::write(
            env.workspace.join(".hatch/hooks/project_new.sh"),
            include_str!("../../templates/hooks/project_new.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write project_new hook: {error}"));
        fs::write(
            env.workspace.join(".hatch/hooks/task_new.sh"),
            include_str!("../../templates/hooks/task_new.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write task_new hook: {error}"));
        fs::write(
            env.workspace.join(".hatch/hooks/task_open.sh"),
            include_str!("../../templates/hooks/task_open.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write task_open hook: {error}"));
        fs::write(
            env.workspace.join(".hatch/hooks/repo_new.sh"),
            include_str!("../../templates/hooks/repo_new.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write repo_new hook: {error}"));
        fs::write(
            env.workspace.join(".hatch/hooks/repo_delete.sh"),
            include_str!("../../templates/hooks/repo_delete.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write repo_delete hook: {error}"));
        fs::write(
            env.workspace.join(".hatch/hooks/agent_start.sh"),
            include_str!("../../templates/hooks/agent_start.sh"),
        )
        .unwrap_or_else(|error| panic!("failed to write agent_start hook: {error}"));
        fs::write(
            env.workspace.join(".hatch/default-repos.txt"),
            include_str!("../../templates/default-repos.txt"),
        )
        .unwrap_or_else(|error| panic!("failed to write default repos file: {error}"));
        fs::write(
            &env.config_file,
            format!("workspace_root = \"{}\"\n", env.workspace.display()),
        )
        .unwrap_or_else(|error| panic!("failed to write hatch config: {error}"));
        env
    }

    pub fn run_stdout(&self, args: &[&str]) -> String {
        String::from_utf8(self.run_output(args, None).stdout)
            .unwrap_or_else(|error| panic!("stdout was not valid UTF-8 for {args:?}: {error}"))
    }

    pub fn run_output(&self, args: &[&str], input: Option<&str>) -> Output {
        let output = self.run_output_allow_failure(args, input);
        assert!(
            output.status.success(),
            "stderr: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        output
    }

    pub fn assert_success(&self, output: &Output) {
        assert!(
            output.status.success(),
            "stdout: {}\nstderr: {}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    pub fn assert_failure_contains(&self, output: &Output, expected: &str) {
        assert!(
            !output.status.success(),
            "expected failure, got stdout: {}\nstderr: {}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            stderr.contains(expected),
            "expected stderr to contain {expected:?}, got: {stderr}"
        );
    }

    pub fn assert_stdout(&self, output: &Output, expected: &str) {
        assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), expected);
    }

    pub fn run_output_allow_failure(&self, args: &[&str], input: Option<&str>) -> Output {
        self.run_output_with_env(args, input, &[])
    }

    pub fn run_output_without_forced_color(&self, args: &[&str], input: Option<&str>) -> Output {
        self.run_output_with_env_in_dir(args, input, &[], None, true, false)
    }

    pub fn run_output_with_env(
        &self,
        args: &[&str],
        input: Option<&str>,
        environment: &[(&str, String)],
    ) -> Output {
        self.run_output_with_env_in_dir(args, input, environment, None, true, true)
    }

    pub fn run_output_with_extra_env_in_dir(
        &self,
        args: &[&str],
        input: Option<&str>,
        environment: &[(&str, String)],
        current_dir: &Path,
    ) -> Output {
        self.run_output_with_env_in_dir(args, input, environment, Some(current_dir), true, true)
    }

    pub fn run_output_in_dir(
        &self,
        args: &[&str],
        input: Option<&str>,
        current_dir: &Path,
    ) -> Output {
        self.run_output_with_env_in_dir(args, input, &[], Some(current_dir), true, true)
    }

    pub fn run_output_allow_failure_in_dir(
        &self,
        args: &[&str],
        input: Option<&str>,
        current_dir: &Path,
    ) -> Output {
        self.run_output_with_env_in_dir(args, input, &[], Some(current_dir), true, true)
    }

    pub fn run_output_discovering_workspace_in_dir(
        &self,
        args: &[&str],
        input: Option<&str>,
        current_dir: &Path,
    ) -> Output {
        self.run_output_with_env_in_dir(args, input, &[], Some(current_dir), false, true)
    }

    fn run_output_with_env_in_dir(
        &self,
        args: &[&str],
        input: Option<&str>,
        environment: &[(&str, String)],
        current_dir: Option<&Path>,
        force_workspace_root: bool,
        force_color: bool,
    ) -> Output {
        let mut command = Command::cargo_bin("hatch")
            .unwrap_or_else(|error| panic!("failed to find hatch test binary: {error}"));
        command.args(args);
        if force_workspace_root {
            command.env("HATCH_TEST_WORKSPACE_ROOT", &self.workspace);
        }
        if let Some(current_dir) = current_dir {
            command.current_dir(current_dir);
        }
        command.env("VISUAL", &self.task_open_stub);
        command.env("HATCH_CONFIG_FILE", &self.config_file);
        command.env("HATCH_TASK_OPEN_LOG", &self.task_open_log);
        if force_color {
            command.env("CLICOLOR_FORCE", "1");
        }
        command.env_remove("NO_COLOR");
        let mut explicit_path: Option<&str> = None;
        for (key, value) in environment {
            if *key == "PATH" {
                explicit_path = Some(value.as_str());
            }
            command.env(key, value);
        }
        let path = self.merged_path(explicit_path);
        command.env("PATH", &path);
        if let Some(input) = input {
            command.write_stdin(input);
        }
        command
            .output()
            .unwrap_or_else(|error| panic!("failed to run hatch {args:?}: {error}"))
    }

    pub fn bin_path(&self) -> PathBuf {
        self.test_bin.clone()
    }

    pub fn install_git(&self, kind: FakeGit) -> PathBuf {
        let path = self.test_bin.join("git");
        write_executable(&path, fake_git::script(kind));
        path
    }

    pub fn install_gh(&self, kind: FakeGh) -> PathBuf {
        let path = self.test_bin.join("gh");
        write_executable(&path, fake_gh::script(kind));
        path
    }

    pub fn remove_tool(&self, name: &str) {
        let _ = fs::remove_file(self.test_bin.join(name));
    }

    pub fn install_editor(&self, name: &str, kind: FakeEditor) -> PathBuf {
        let path = self.test_bin.join(name);
        write_executable(&path, fake_editor::script(kind));
        path
    }

    pub fn install_hook(&self, path: impl AsRef<Path>, kind: FakeHook) {
        write_executable(path.as_ref(), fake_hook::script(kind));
    }

    pub fn path_env(&self) -> String {
        self.merged_path(None)
    }

    pub fn config_file(&self) -> &Path {
        &self.config_file
    }

    pub fn path(&self, relative: &str) -> PathBuf {
        self.workspace.join(relative)
    }

    pub fn mkdir(&self, relative: &str) {
        let path = self.path(relative);
        fs::create_dir_all(&path)
            .unwrap_or_else(|error| panic!("failed to create {}: {error}", path.display()));
    }

    pub fn write(&self, relative: &str, data: impl AsRef<[u8]>) {
        let path = self.path(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap_or_else(|error| {
                panic!("failed to create parent {}: {error}", parent.display())
            });
        }
        fs::write(&path, data)
            .unwrap_or_else(|error| panic!("failed to write {}: {error}", path.display()));
    }

    pub fn read(&self, relative: &str) -> String {
        let path = self.path(relative);
        fs::read_to_string(&path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()))
    }

    pub fn project(&self, name: &str) -> PathBuf {
        let path = self.path(name);
        self.mkdir(&format!("{name}/.hatch"));
        path
    }

    pub fn project_marker(&self, project: &str) {
        self.mkdir(&format!("{project}/.hatch"));
    }

    pub fn task(&self, project: &str, task: &str) -> PathBuf {
        self.project(project);
        let path = self.path(&format!("{project}/{task}"));
        self.mkdir(&format!("{project}/{task}"));
        path
    }

    pub fn repo_marker(&self, project: &str, task: &str, repo: &str, origin: &str) -> PathBuf {
        let path = self.task(project, task).join(repo);
        fs::create_dir_all(path.join(".git")).unwrap_or_else(|error| {
            panic!("failed to create repo marker {}: {error}", path.display())
        });
        fs::write(path.join(".origin"), origin).unwrap_or_else(|error| {
            panic!("failed to write repo origin {}: {error}", path.display())
        });
        path
    }

    fn merged_path(&self, explicit_path: Option<&str>) -> String {
        let test_bin = self.test_bin.to_string_lossy();
        let hatch_binary = Path::new(assert_cmd::cargo::cargo_bin("hatch").as_os_str())
            .parent()
            .map(|path| path.to_string_lossy().to_string())
            .unwrap_or_default();
        let base_path = explicit_path
            .map(ToString::to_string)
            .unwrap_or_else(|| std::env::var("PATH").unwrap_or_default());
        let mut segments: Vec<String> = base_path
            .split(':')
            .filter_map(|segment| {
                let segment = segment.trim();
                if segment.is_empty() {
                    None
                } else {
                    Some(segment.to_string())
                }
            })
            .collect();
        let has_explicit = explicit_path.is_some();
        if !hatch_binary.is_empty() && !segments.iter().any(|segment| segment == &hatch_binary) {
            segments.insert(0, hatch_binary.clone());
        }
        if !has_explicit && !segments.iter().any(|segment| segment == &*test_bin) {
            if segments.is_empty() {
                segments.push(test_bin.to_string());
            } else {
                segments.insert(1, test_bin.to_string());
            }
        }
        segments.join(":")
    }
}

fn write_executable(path: &Path, script: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap_or_else(|error| {
            panic!("failed to create parent {}: {error}", parent.display())
        });
    }
    fs::write(path, script)
        .unwrap_or_else(|error| panic!("failed to write script {}: {error}", path.display()));
    make_executable(path);
}

const TASK_OPEN_STUB: &str = "#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"$HATCH_TASK_OPEN_LOG\"\n";
