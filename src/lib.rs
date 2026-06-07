mod discovery;
mod environment;
mod error;
mod git;
mod github;
mod hooks;
#[doc(hidden)]
pub mod matching;
mod model;
mod process;
mod repo;
pub mod terminal;
mod workspace;

pub use discovery::WorkspaceDiscovery;
pub use environment::{HatchEnvironment, HatchStore};
pub use error::{Error, Result};
pub use model::{
    AddRepoRequest, AppPaths, CleanupCandidate, ProjectCreateRequest, ProjectSummary,
    TaskCreateRequest, TaskSummary,
};
pub(crate) use model::{ProjectCreationPlan, TaskCreationPlan, TaskRepoSummary};
pub use workspace::{CleanupCandidateView, WorkspaceService};
