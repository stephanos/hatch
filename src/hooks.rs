use crate::process::ProcessRunner;
use crate::{AppPaths, Result};
use camino::{Utf8Path, Utf8PathBuf};
use std::collections::BTreeMap;

#[derive(Debug, Clone)]
pub struct HookContext {
    pub workspace_root: Utf8PathBuf,
    pub workspace_hooks_directory: Utf8PathBuf,
    pub project_hooks_directory: Option<Utf8PathBuf>,
    pub project_path: Option<Utf8PathBuf>,
    pub task_path: Option<Utf8PathBuf>,
    pub clone_url: Option<String>,
    pub repo_path: Option<Utf8PathBuf>,
    pub base_branch: Option<String>,
    pub extra_args: Vec<String>,
    pub forwarded_args: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum HookName {
    ProjectNew,
    TaskNew,
    TaskOpen,
    RepoNew,
    RepoDelete,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct HookDefinition {
    name: &'static str,
    legacy_names: &'static [&'static str],
    default_template: &'static str,
}

impl HookName {
    pub(crate) fn all() -> [Self; 5] {
        [
            Self::ProjectNew,
            Self::TaskNew,
            Self::TaskOpen,
            Self::RepoNew,
            Self::RepoDelete,
        ]
    }

    pub(crate) fn as_str(self) -> &'static str {
        self.definition().name
    }

    pub(crate) fn default_template(self) -> &'static str {
        self.definition().default_template
    }

    pub(crate) fn from_name(value: &str) -> Result<Self> {
        Self::all()
            .into_iter()
            .find(|hook| hook.as_str() == value || hook.legacy_names().contains(&value))
            .ok_or_else(|| crate::Error::Message(format!("unknown hook: {value}")))
    }

    fn legacy_names(self) -> &'static [&'static str] {
        self.definition().legacy_names
    }

    fn definition(self) -> HookDefinition {
        match self {
            Self::ProjectNew => HookDefinition {
                name: "project_new",
                legacy_names: &["project_create"],
                default_template: include_str!("../templates/hooks/project_new.sh"),
            },
            Self::TaskNew => HookDefinition {
                name: "task_new",
                legacy_names: &["task_create"],
                default_template: include_str!("../templates/hooks/task_new.sh"),
            },
            Self::TaskOpen => HookDefinition {
                name: "task_open",
                legacy_names: &[],
                default_template: include_str!("../templates/hooks/task_open.sh"),
            },
            Self::RepoNew => HookDefinition {
                name: "repo_new",
                legacy_names: &["repo_add"],
                default_template: include_str!("../templates/hooks/repo_new.sh"),
            },
            Self::RepoDelete => HookDefinition {
                name: "repo_delete",
                legacy_names: &["repo_cleanup", "cleanup"],
                default_template: include_str!("../templates/hooks/repo_delete.sh"),
            },
        }
    }
}

#[derive(Debug, Default, Clone)]
pub struct HookRunner {
    process: ProcessRunner,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HookOutcome {
    Missing,
    RanSilent {
        hook_file: Utf8PathBuf,
    },
    RanWithOutput {
        hook_file: Utf8PathBuf,
        output: String,
    },
}

impl HookRunner {
    pub fn run_outcome(&self, name: HookName, context: &HookContext) -> Result<HookOutcome> {
        self.run_outcome_with_output_mode(name, context, HookOutputMode::Stream)
    }

    pub fn run_outcome_captured(
        &self,
        name: HookName,
        context: &HookContext,
    ) -> Result<HookOutcome> {
        self.run_outcome_with_output_mode(name, context, HookOutputMode::Capture)
    }

    pub fn run_workspace_outcome(
        &self,
        name: HookName,
        context: &HookContext,
    ) -> Result<HookOutcome> {
        let mut context = context.clone();
        context.project_hooks_directory = None;
        self.run_outcome_with_output_mode(name, &context, HookOutputMode::Stream)
    }

    fn run_outcome_with_output_mode(
        &self,
        name: HookName,
        context: &HookContext,
        output_mode: HookOutputMode,
    ) -> Result<HookOutcome> {
        let mut candidates = vec![name.as_str().to_string()];
        candidates.extend(name.legacy_names().iter().map(|name| name.to_string()));
        let hook_file = candidates
            .into_iter()
            .flat_map(|hook| self.hook_candidates(context, &hook))
            .find(|file| file.exists());
        let Some(hook_file) = hook_file else {
            return Ok(HookOutcome::Missing);
        };
        let current_directory = [
            &context.repo_path,
            &context.task_path,
            &context.project_path,
        ]
        .into_iter()
        .flatten()
        .find(|path| path.exists())
        .unwrap_or(&context.workspace_root);
        let mut arguments = Vec::with_capacity(context.flag_arguments().len() + 1);
        arguments.push(hook_file.to_string());
        arguments.extend(context.flag_arguments());
        let mut environment = BTreeMap::new();
        let hook_lib_directory = context
            .workspace_hooks_directory
            .parent()
            .map(|path| path.join("lib"))
            .unwrap_or_else(|| context.workspace_hooks_directory.join("lib"));
        environment.insert(
            "HATCH_HOOK_LIB_DIR".to_string(),
            hook_lib_directory.to_string(),
        );
        environment.insert(
            crate::terminal::HOOK_STATUS_COLOR_ENV.to_string(),
            crate::terminal::HOOK_STATUS_COLOR_ALWAYS.to_string(),
        );
        if matches!(output_mode, HookOutputMode::Stream) {
            crate::terminal::print_hook_status(&hook_file);
        }
        let output = match output_mode {
            HookOutputMode::Stream => self.process.run_streaming(
                "sh",
                &arguments,
                Some(current_directory),
                Some(&environment),
            ),
            HookOutputMode::Capture => self.process.run(
                "sh",
                &arguments,
                Some(current_directory),
                Some(&environment),
            ),
        }
        .map_err(|source| crate::Error::Message(format!("hook {hook_file} failed: {source}")))?;
        if output.is_empty() {
            Ok(HookOutcome::RanSilent { hook_file })
        } else {
            Ok(HookOutcome::RanWithOutput { hook_file, output })
        }
    }

    fn hook_candidates(&self, context: &HookContext, hook: &str) -> Vec<Utf8PathBuf> {
        let workspace_hook = context.workspace_hooks_directory.join(format!("{hook}.sh"));
        let mut candidates = Vec::new();
        if let Some(project_hooks) = &context.project_hooks_directory {
            candidates.push(project_hooks.join(format!("{hook}.sh")));
        }
        candidates.push(workspace_hook);
        candidates
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HookOutputMode {
    Stream,
    Capture,
}

impl HookOutcome {
    pub fn hook_file(&self) -> Option<&Utf8PathBuf> {
        match self {
            Self::Missing => None,
            Self::RanSilent { hook_file } | Self::RanWithOutput { hook_file, .. } => {
                Some(hook_file)
            }
        }
    }

    pub fn output(&self) -> Option<&str> {
        match self {
            Self::Missing | Self::RanSilent { .. } => None,
            Self::RanWithOutput { output, .. } => Some(output),
        }
    }
}

pub fn print_hook_outcome(outcome: &HookOutcome) {
    let _ = outcome;
}

impl HookContext {
    pub(crate) fn workspace(paths: &AppPaths) -> Self {
        Self {
            workspace_root: paths.workspace_root.clone(),
            workspace_hooks_directory: paths.hooks_directory.clone(),
            project_hooks_directory: None,
            project_path: None,
            task_path: None,
            clone_url: None,
            repo_path: None,
            base_branch: None,
            extra_args: Vec::new(),
            forwarded_args: Vec::new(),
        }
    }

    pub(crate) fn project(paths: &AppPaths, project_path: &Utf8Path) -> Self {
        let mut context = Self::workspace(paths);
        context.project_path = Some(project_path.to_path_buf());
        context.project_hooks_directory = Some(project_hooks_directory(project_path));
        context
    }

    pub(crate) fn task(paths: &AppPaths, project_path: &Utf8Path, task_path: &Utf8Path) -> Self {
        let mut context = Self::project(paths, project_path);
        context.task_path = Some(task_path.to_path_buf());
        context
    }

    pub(crate) fn repo_new(
        paths: &AppPaths,
        project_path: &Utf8Path,
        task_path: &Utf8Path,
        repo_path: &Utf8Path,
        clone_url: String,
        base_branch: Option<String>,
    ) -> Self {
        let mut context = Self::task(paths, project_path, task_path);
        context.clone_url = Some(clone_url);
        context.repo_path = Some(repo_path.to_path_buf());
        context.base_branch = base_branch;
        context
    }

    pub(crate) fn repo_delete(
        paths: &AppPaths,
        project_path: &Utf8Path,
        task_path: &Utf8Path,
        repo_path: &Utf8Path,
        dry_run: bool,
    ) -> Self {
        let mut context = Self::task(paths, project_path, task_path);
        context.repo_path = Some(repo_path.to_path_buf());
        if dry_run {
            context.extra_args.push("--dry-run".to_string());
        }
        context
    }

    pub(crate) fn with_forwarded_args(mut self, args: &[String]) -> Self {
        let mut index = 0;
        while index < args.len() {
            let Some(value) = args.get(index + 1) else {
                break;
            };
            match args[index].as_str() {
                "--project-path" => self.project_path = Some(value.into()),
                "--task-path" => self.task_path = Some(value.into()),
                "--clone-url" => self.clone_url = Some(value.clone()),
                "--repo-path" => self.repo_path = Some(value.into()),
                "--base-branch" => self.base_branch = Some(value.clone()),
                _ => {
                    index += 1;
                    continue;
                }
            }
            index += 2;
        }
        self.extra_args = args.to_vec();
        self
    }

    fn flag_arguments(&self) -> Vec<String> {
        let mut arguments = Vec::new();
        if let Some(value) = &self.project_path {
            arguments.push("--project-path".to_string());
            arguments.push(value.to_string());
        }
        if let Some(value) = &self.task_path {
            arguments.push("--task-path".to_string());
            arguments.push(value.to_string());
        }
        if let Some(value) = &self.clone_url {
            arguments.push("--clone-url".to_string());
            arguments.push(value.clone());
        }
        if let Some(value) = &self.repo_path {
            arguments.push("--repo-path".to_string());
            arguments.push(value.to_string());
        }
        if let Some(value) = &self.base_branch {
            arguments.push("--base-branch".to_string());
            arguments.push(value.clone());
        }
        arguments.extend(self.extra_args.iter().cloned());
        if !self.forwarded_args.is_empty() {
            arguments.push("--".to_string());
            arguments.extend(self.forwarded_args.iter().cloned());
        }
        arguments
    }
}

fn project_hooks_directory(project_path: &Utf8Path) -> Utf8PathBuf {
    project_path.join(".hatch").join("hooks")
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn test_context(root: &camino::Utf8Path) -> HookContext {
        HookContext {
            workspace_root: root.to_path_buf(),
            workspace_hooks_directory: root.join("hooks"),
            project_hooks_directory: None,
            project_path: None,
            task_path: None,
            clone_url: None,
            repo_path: None,
            base_branch: None,
            extra_args: Vec::new(),
            forwarded_args: Vec::new(),
        }
    }

    #[cfg(unix)]
    fn write_executable(path: &camino::Utf8Path, script: &str) {
        use std::os::unix::fs::PermissionsExt;

        fs_err::create_dir_all(
            path.parent()
                .unwrap_or_else(|| panic!("hook path should have a parent: {path}")),
        )
        .unwrap_or_else(|error| panic!("failed to create hook dir for {path}: {error}"));
        fs_err::write(path, script)
            .unwrap_or_else(|error| panic!("failed to write hook script {path}: {error}"));
        let metadata = fs_err::metadata(path)
            .unwrap_or_else(|error| panic!("failed to read metadata for {path}: {error}"));
        let mut permissions = metadata.permissions();
        permissions.set_mode(0o755);
        fs_err::set_permissions(path, permissions)
            .unwrap_or_else(|error| panic!("failed to chmod hook script {path}: {error}"));
    }

    #[test]
    fn reports_missing_hook_when_no_hook_file_exists() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = camino::Utf8PathBuf::from_path_buf(temp.path().to_path_buf())
            .unwrap_or_else(|path| panic!("temp path must be UTF-8: {}", path.display()));
        let runner = HookRunner::default();

        let outcome = runner.run_outcome(HookName::TaskOpen, &test_context(&root));

        assert!(matches!(outcome, Ok(HookOutcome::Missing)));
    }

    #[cfg(unix)]
    #[test]
    fn reports_silent_hook_when_hook_emits_no_output() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = camino::Utf8PathBuf::from_path_buf(temp.path().to_path_buf())
            .unwrap_or_else(|path| panic!("temp path must be UTF-8: {}", path.display()));
        let hook = root.join("hooks/task_open.sh");
        write_executable(&hook, "#!/usr/bin/env sh\n");
        let runner = HookRunner::default();

        let outcome = runner.run_outcome(HookName::TaskOpen, &test_context(&root));

        assert!(matches!(
            outcome,
            Ok(HookOutcome::RanSilent { hook_file }) if hook_file == hook
        ));
    }

    #[cfg(unix)]
    #[test]
    fn reports_hook_output_when_hook_prints_text() {
        let temp = tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let root = camino::Utf8PathBuf::from_path_buf(temp.path().to_path_buf())
            .unwrap_or_else(|path| panic!("temp path must be UTF-8: {}", path.display()));
        let hook = root.join("hooks/task_open.sh");
        write_executable(&hook, "#!/usr/bin/env sh\nprintf 'hello\\n'\n");
        let runner = HookRunner::default();

        let outcome = runner.run_outcome(HookName::TaskOpen, &test_context(&root));

        assert!(matches!(
            outcome,
            Ok(HookOutcome::RanWithOutput { hook_file, output })
                if hook_file == hook && output == "hello"
        ));
    }
}
