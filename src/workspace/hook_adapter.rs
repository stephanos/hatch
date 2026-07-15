use crate::hooks::{HookName, HookOutcome};
use crate::{AppPaths, Error, Result};
use camino::Utf8Path;

use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone)]
pub(crate) struct WorkspaceHookAdapter {
    core: WorkspaceServiceCore,
}

impl WorkspaceHookAdapter {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn run_task_new(
        &self,
        paths: &AppPaths,
        project_path: &Utf8Path,
        task_path: &Utf8Path,
    ) -> Result<HookOutcome> {
        self.run_printed(
            HookName::TaskNew,
            &crate::hooks::HookContext::task(paths, project_path, task_path),
        )
    }

    pub(crate) fn run_task_open(
        &self,
        paths: &AppPaths,
        project_path: &Utf8Path,
        task_path: &Utf8Path,
    ) -> Result<HookOutcome> {
        self.run_printed(
            HookName::TaskOpen,
            &crate::hooks::HookContext::task(paths, project_path, task_path),
        )
    }

    pub(crate) fn run_required_repo_new(&self, hook: RepoNewHook<'_>) -> Result<HookOutcome> {
        let context = crate::hooks::HookContext::repo_new(
            hook.paths,
            hook.project_path,
            hook.task_path,
            hook.repo_path,
            hook.clone_url.to_string(),
            hook.base_branch.clone(),
        );
        let outcome = self.run_unprinted(HookName::RepoNew, &context)?;
        if matches!(outcome, HookOutcome::Missing) {
            let project_hook = hook
                .project_path
                .join(".hatch")
                .join("hooks")
                .join("repo_new.sh");
            let workspace_hook = hook.paths.hooks_directory.join("repo_new.sh");
            return Err(Error::Message(format!(
                "repo_new hook not found; checked {project_hook} and {workspace_hook}"
            )));
        }
        Ok(outcome)
    }

    pub(crate) fn capture_repo_delete_dry_run(
        &self,
        hook: RepoDeleteHook<'_>,
    ) -> Option<HookOutcome> {
        let context = repo_delete_context(hook, true);
        self.core
            .hooks
            .run_outcome_captured(HookName::RepoDelete, &context)
            .ok()
    }

    pub(crate) fn run_repo_delete(&self, hook: RepoDeleteHook<'_>) -> Result<HookOutcome> {
        let context = repo_delete_context(hook, false);
        self.run_printed(HookName::RepoDelete, &context)
    }

    pub(crate) fn run_workspace_hook(
        &self,
        paths: &AppPaths,
        hook: HookName,
        args: &[String],
    ) -> Result<HookOutcome> {
        let context = crate::hooks::HookContext::workspace(paths).with_forwarded_args(args);
        let outcome = self.core.hooks.run_workspace_outcome(hook, &context)?;
        if matches!(outcome, HookOutcome::Missing) {
            return Err(Error::Message(format!(
                "workspace hook not found: {hook_name}",
                hook_name = hook.as_str()
            )));
        }
        crate::hooks::print_hook_outcome(&outcome);
        Ok(outcome)
    }

    fn run_printed(
        &self,
        name: HookName,
        context: &crate::hooks::HookContext,
    ) -> Result<HookOutcome> {
        let outcome = self.run_unprinted(name, context)?;
        crate::hooks::print_hook_outcome(&outcome);
        Ok(outcome)
    }

    fn run_unprinted(
        &self,
        name: HookName,
        context: &crate::hooks::HookContext,
    ) -> Result<HookOutcome> {
        self.core.hooks.run_outcome(name, context)
    }
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct RepoNewHook<'a> {
    pub(crate) paths: &'a AppPaths,
    pub(crate) project_path: &'a Utf8Path,
    pub(crate) task_path: &'a Utf8Path,
    pub(crate) repo_path: &'a Utf8Path,
    pub(crate) clone_url: &'a str,
    pub(crate) base_branch: &'a Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct RepoDeleteHook<'a> {
    pub(crate) paths: &'a AppPaths,
    pub(crate) project_path: &'a Utf8Path,
    pub(crate) task_path: &'a Utf8Path,
    pub(crate) repo_path: &'a Utf8Path,
}

fn repo_delete_context(hook: RepoDeleteHook<'_>, dry_run: bool) -> crate::hooks::HookContext {
    crate::hooks::HookContext::repo_delete(
        hook.paths,
        hook.project_path,
        hook.task_path,
        hook.repo_path,
        dry_run,
    )
}
