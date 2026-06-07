use camino::Utf8PathBuf;
use fs_err as fs;
use hatch::{HatchEnvironment, HatchStore, WorkspaceDiscovery};

#[test]
fn loads_workspace_and_discovers_projects_and_tasks() {
    let temp =
        tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
    let root = Utf8PathBuf::from_path_buf(temp.path().to_path_buf())
        .expect("tempdir path must be valid UTF-8");
    let workspace = root.join("Workspace");
    fs::create_dir_all(workspace.join(".hatch"))
        .unwrap_or_else(|error| panic!("failed to create workspace hatch dir: {error}"));
    fs::create_dir_all(workspace.join("api/task-one"))
        .unwrap_or_else(|error| panic!("failed to create api/task-one: {error}"));
    fs::create_dir_all(workspace.join("api/task-two"))
        .unwrap_or_else(|error| panic!("failed to create api/task-two: {error}"));
    fs::create_dir_all(workspace.join("web/task-three"))
        .unwrap_or_else(|error| panic!("failed to create web/task-three: {error}"));
    fs::create_dir_all(workspace.join("api/.hatch"))
        .unwrap_or_else(|error| panic!("failed to create api hatch dir: {error}"));
    fs::create_dir_all(workspace.join("web/.hatch"))
        .unwrap_or_else(|error| panic!("failed to create web hatch dir: {error}"));

    let store = HatchStore::new(HatchEnvironment::new(Some(workspace.clone())));
    let paths = store
        .paths()
        .unwrap_or_else(|error| panic!("failed to load paths: {error}"));

    let discovery = WorkspaceDiscovery;
    let projects = discovery
        .list_projects(&paths)
        .unwrap_or_else(|error| panic!("failed to list projects: {error}"));
    assert_eq!(
        projects
            .iter()
            .map(|project| project.name.as_str())
            .collect::<Vec<_>>(),
        ["api", "web"]
    );

    let tasks = discovery
        .list_tasks(&paths)
        .unwrap_or_else(|error| panic!("failed to list tasks: {error}"));
    assert_eq!(
        tasks
            .iter()
            .map(|task| task.id.as_str())
            .collect::<Vec<_>>(),
        ["api/task-one", "api/task-two", "web/task-three"]
    );
}
