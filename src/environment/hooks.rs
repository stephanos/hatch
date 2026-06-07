use crate::error::{IoResultExt, Result};
use crate::hooks::HookName;
use camino::Utf8Path;

const DEFAULT_HOOK_HEADER_SEPARATOR: &str = "\n\n";

#[derive(Debug, Clone, Default)]
pub(crate) struct HookInstaller;

impl HookInstaller {
    pub(crate) fn new() -> Self {
        Self
    }

    pub(crate) fn ensure_workspace_hooks(&self, hooks_directory: &Utf8Path) -> Result<()> {
        fs_err::create_dir_all(hooks_directory).at_path(hooks_directory)?;
        self.write_hook_lib_files(hooks_directory)?;
        self.write_default_repos_file(hooks_directory)?;
        for hook in HookName::all() {
            self.sync_workspace_hook(hooks_directory, hook)?;
        }
        Ok(())
    }

    pub(crate) fn ensure_project_hooks(&self, hooks_directory: &Utf8Path) -> Result<()> {
        fs_err::create_dir_all(hooks_directory).at_path(hooks_directory)?;
        self.write_default_repos_file(hooks_directory)?;
        for hook in HookName::all() {
            let name = hook.as_str();
            self.write_project_hook(&hooks_directory.join(format!("{name}.sh")), name)?;
        }
        Ok(())
    }

    pub(crate) fn sync_workspace_hooks(&self, hooks_directory: &Utf8Path) -> Result<()> {
        if !hooks_directory.exists() {
            return Ok(());
        }
        fs_err::create_dir_all(hooks_directory).at_path(hooks_directory)?;
        self.write_hook_lib_files(hooks_directory)?;
        for hook in HookName::all() {
            self.sync_workspace_hook(hooks_directory, hook)?;
        }
        Ok(())
    }

    fn sync_workspace_hook(&self, hooks_directory: &Utf8Path, hook: HookName) -> Result<()> {
        let name = hook.as_str();
        let path = hooks_directory.join(format!("{name}.sh"));
        let default_path = hooks_directory.join(format!("{name}.default.sh"));
        let data = hook.default_template();
        let previous_default = if default_path.exists() {
            Some(fs_err::read_to_string(&default_path).at_path(&default_path)?)
        } else {
            None
        };
        let should_write_hook = if path.exists() {
            if let Some(previous_default) = previous_default.as_deref() {
                let hook_data = fs_err::read_to_string(&path).at_path(&path)?;
                hook_body(&hook_data) == hook_body(previous_default)
            } else {
                false
            }
        } else {
            true
        };
        if should_write_hook {
            fs_err::write(&path, data).at_path(&path)?;
            self.make_executable(&path)?;
        }
        let default_data = workspace_default_hook_data(name, data);
        fs_err::write(&default_path, default_data).at_path(&default_path)?;
        self.make_executable(&default_path)
    }

    fn write_project_hook(&self, path: &Utf8Path, hook_name: &str) -> Result<()> {
        if path.exists() {
            return Ok(());
        }
        let mut data = include_str!("../../templates/hooks/project_hook_wrapper.sh").to_string();
        data = data.replace("{HOOK_NAME}", hook_name);
        fs_err::write(path, data).at_path(path)?;
        self.make_executable(path)
    }

    fn write_hook_lib_files(&self, hooks_directory: &Utf8Path) -> Result<()> {
        let lib_directory = hooks_directory.join("lib");
        fs_err::create_dir_all(&lib_directory).at_path(&lib_directory)?;
        for (filename, data) in [
            (
                "hatch.sh",
                include_str!("../../templates/hooks/lib/hatch.sh"),
            ),
            ("args.sh", include_str!("../../templates/hooks/lib/args.sh")),
            ("path.sh", include_str!("../../templates/hooks/lib/path.sh")),
            ("repo.sh", include_str!("../../templates/hooks/lib/repo.sh")),
        ] {
            self.write_hook_lib_file(&lib_directory.join(filename), data)?;
        }
        Ok(())
    }

    fn write_hook_lib_file(&self, path: &Utf8Path, data: &str) -> Result<()> {
        fs_err::write(path, data).at_path(path)?;
        self.make_executable(path)
    }

    fn write_default_repos_file(&self, hooks_directory: &Utf8Path) -> Result<()> {
        let Some(hatch_directory) = hooks_directory.parent() else {
            return Ok(());
        };
        let path = hatch_directory.join("default_repos.txt");
        if path.exists() {
            return Ok(());
        }
        fs_err::write(&path, include_str!("../../templates/default_repos.txt")).at_path(&path)
    }

    fn make_executable(&self, path: &Utf8Path) -> Result<()> {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut permissions = fs_err::metadata(path).at_path(path)?.permissions();
            permissions.set_mode(0o755);
            fs_err::set_permissions(path, permissions).at_path(path)?;
        }
        Ok(())
    }
}

fn workspace_default_hook_data(name: &str, data: &str) -> String {
    format!(
        "{}{}{}",
        workspace_default_hook_header(name),
        DEFAULT_HOOK_HEADER_SEPARATOR,
        data
    )
}

fn workspace_default_hook_header(name: &str) -> String {
    format!(
        "# This is Hatch's bundled default hook for {name}.\n\
         # Hatch rewrites this file when its bundled defaults change.\n\
         # Edit {name}.sh to customize behavior; Hatch only upgrades it while it still matches a previous default."
    )
}

fn hook_body(data: &str) -> &str {
    if data.starts_with("# This is Hatch's bundled default hook for ")
        && let Some((_, body)) = data.split_once(DEFAULT_HOOK_HEADER_SEPARATOR)
    {
        return body;
    }
    data
}
