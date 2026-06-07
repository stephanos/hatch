use crate::hooks::HookName;
use crate::matching::{format_ambiguous_query, fuzzy_score};
use crate::workspace::helpers::{ensure_path_absent, run_with_rollback, validate_identifier};
use crate::{AppPaths, Error, ProjectCreateRequest, ProjectCreationPlan, ProjectSummary, Result};

use super::query::{QueryResolution, resolve_query};
use super::shared::WorkspaceServiceCore;

#[derive(Debug, Clone)]
pub(crate) struct ProjectService {
    core: WorkspaceServiceCore,
}

impl ProjectService {
    pub(crate) fn new(core: WorkspaceServiceCore) -> Self {
        Self { core }
    }

    pub(crate) fn list_projects(&self, paths: &AppPaths) -> Result<Vec<ProjectSummary>> {
        self.core.discovery.list_projects(paths)
    }

    pub(crate) fn resolve_project_query(
        &self,
        paths: &AppPaths,
        query: &str,
    ) -> Result<ProjectSummary> {
        let query = query.trim();
        if query.is_empty() {
            return Err(Error::Message("project query cannot be empty".to_string()));
        }
        let projects = self.list_projects(paths)?;
        match resolve_query(
            query,
            projects,
            |project| [project.id.clone(), project.name.clone()],
            |project, query| {
                fuzzy_score(&project.name, query).or_else(|| fuzzy_score(&project.id, query))
            },
            |project| project.name.as_str(),
            |project| project.id.clone(),
        ) {
            QueryResolution::Match(project) => Ok(project),
            QueryResolution::NotFound => {
                Err(Error::Message(format!("no project matches: {query}")))
            }
            QueryResolution::Ambiguous(candidates) => Err(Error::Message(format_ambiguous_query(
                "project",
                query,
                &candidates,
            ))),
        }
    }

    pub(crate) fn create_project(
        &self,
        paths: &AppPaths,
        request: ProjectCreateRequest,
    ) -> Result<ProjectSummary> {
        let plan = self.plan_project_creation(paths, &request.name)?;
        let name = plan.project.clone();
        let force = request.force;
        fs_err::create_dir_all(&paths.workspace_root).map_err(|source| Error::Io {
            path: paths.workspace_root.clone().into_std_path_buf(),
            source,
        })?;
        let project_path = plan.project_directory.clone();
        if force {
            if project_path.exists() && !project_path.is_dir() {
                return Err(Error::Message(format!("{project_path} already exists")));
            }
            let hatch_path = project_path.join(".hatch");
            if hatch_path.exists() {
                fs_err::remove_dir_all(&hatch_path).map_err(|source| Error::Io {
                    path: hatch_path.clone().into_std_path_buf(),
                    source,
                })?;
            }
        } else {
            ensure_path_absent(&project_path)?;
        }
        let context = Self::project_new_hook_context(paths, &project_path);
        let rollback_path = if force {
            project_path.join(".hatch")
        } else {
            project_path.clone()
        };
        run_with_rollback(&rollback_path, || {
            fs_err::create_dir_all(&project_path).map_err(|source| Error::Io {
                path: project_path.clone().into_std_path_buf(),
                source,
            })?;
            self.core
                .store
                .ensure_project_hook_files(&project_path.join(".hatch").join("hooks"))?;
            let outcome = self
                .core
                .hooks
                .run_workspace_outcome(HookName::ProjectNew, &context)?;
            crate::hooks::print_hook_outcome(&outcome);
            Ok(ProjectSummary {
                id: name.clone(),
                name,
                path: project_path.clone(),
            })
        })
    }

    pub(crate) fn plan_project_creation(
        &self,
        paths: &AppPaths,
        name: &str,
    ) -> Result<ProjectCreationPlan> {
        let name = validate_identifier("project name", name)?;
        let project_directory = self.core.project_path(paths, &name);
        Ok(ProjectCreationPlan {
            project: name,
            project_directory,
        })
    }

    fn project_new_hook_context(
        paths: &AppPaths,
        project_path: &camino::Utf8Path,
    ) -> crate::hooks::HookContext {
        crate::hooks::HookContext::project(paths, project_path)
    }

    pub(crate) fn delete_project(&self, paths: &AppPaths, query: &str) -> Result<ProjectSummary> {
        let project = self.resolve_project_query(paths, query)?;
        fs_err::remove_dir_all(&project.path).map_err(|source| Error::Io {
            path: project.path.clone().into_std_path_buf(),
            source,
        })?;
        Ok(project)
    }
}
