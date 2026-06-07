#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

pub fn make_executable(path: &Path) {
    #[cfg(unix)]
    {
        let metadata = fs_err::metadata(path)
            .unwrap_or_else(|error| panic!("failed to stat {}: {error}", path.display()));
        let mut permissions = metadata.permissions();
        permissions.set_mode(0o755);
        fs_err::set_permissions(path, permissions)
            .unwrap_or_else(|error| panic!("failed to chmod {}: {error}", path.display()));
    }
}

pub fn make_git_repo_with_origin(path: &Path, origin: &str) {
    fs_err::create_dir_all(path)
        .unwrap_or_else(|error| panic!("failed to create repo dir {}: {error}", path.display()));
    fs_err::write(path.join(".origin"), origin)
        .unwrap_or_else(|error| panic!("failed to write origin for {}: {error}", path.display()));
    let status = std::process::Command::new("git")
        .args(["init"])
        .arg(path)
        .status()
        .unwrap_or_else(|error| panic!("failed to run git init {}: {error}", path.display()));
    assert!(status.success());
    let status = std::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["remote", "add", "origin", origin])
        .status()
        .unwrap_or_else(|error| panic!("failed to add git origin for {}: {error}", path.display()));
    assert!(status.success());
}
