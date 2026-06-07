use anyhow::Context;
use nono::{AccessMode, CapabilitySet};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PathAdmission {
    path: PathBuf,
    mode: AccessMode,
    required: bool,
    file_only: bool,
}

impl PathAdmission {
    pub(crate) fn required(path: impl Into<PathBuf>, mode: AccessMode) -> Self {
        Self {
            path: path.into(),
            mode,
            required: true,
            file_only: false,
        }
    }

    pub(crate) fn optional_path(path: impl Into<PathBuf>, mode: AccessMode) -> Self {
        Self {
            path: path.into(),
            mode,
            required: false,
            file_only: false,
        }
    }

    pub(crate) fn optional_file(path: impl Into<PathBuf>, mode: AccessMode) -> Self {
        Self {
            path: path.into(),
            mode,
            required: false,
            file_only: true,
        }
    }

    pub(crate) fn apply(self, caps: CapabilitySet) -> anyhow::Result<CapabilitySet> {
        if self.file_only {
            return self.apply_file(caps);
        }
        if self.path.exists() {
            add_existing_path(caps, &self.path, self.mode)
        } else if self.required {
            let _ = fs_err::metadata(&self.path)
                .with_context(|| format!("failed to read sandbox path {}", self.path.display()))?;
            Ok(caps)
        } else {
            Ok(caps)
        }
    }

    fn apply_file(self, caps: CapabilitySet) -> anyhow::Result<CapabilitySet> {
        if self.path.is_file() {
            caps.allow_file(&self.path, self.mode)
                .with_context(|| format!("failed to allow profile file {}", self.path.display()))
        } else if self.required {
            let _ = fs_err::metadata(&self.path)
                .with_context(|| format!("failed to read sandbox path {}", self.path.display()))?;
            Ok(caps)
        } else {
            Ok(caps)
        }
    }
}

fn add_existing_path(
    caps: CapabilitySet,
    path: &Path,
    mode: AccessMode,
) -> anyhow::Result<CapabilitySet> {
    let metadata = fs_err::metadata(path)
        .with_context(|| format!("failed to read sandbox path {}", path.display()))?;
    if metadata.is_dir() {
        caps.allow_path(path, mode)
            .with_context(|| format!("failed to allow directory {}", path.display()))
    } else {
        caps.allow_file(path, mode)
            .with_context(|| format!("failed to allow file {}", path.display()))
    }
}
