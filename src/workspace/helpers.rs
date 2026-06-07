use crate::{Error, Result};
use camino::Utf8Path;

pub(crate) fn validate_identifier(label: &str, value: &str) -> Result<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(Error::Message(format!("{label} cannot be empty")));
    }
    if !trimmed
        .chars()
        .all(|character| character.is_ascii_alphanumeric() || character == '_' || character == '-')
    {
        return Err(Error::Message(format!("{label} must match [a-zA-Z0-9_-]+")));
    }
    Ok(trimmed.to_string())
}

pub(crate) fn ensure_path_absent(path: &Utf8Path) -> Result<()> {
    if path.exists() {
        return Err(Error::Message(format!("{path} already exists")));
    }
    Ok(())
}

pub(crate) fn run_with_rollback<T>(
    path: &Utf8Path,
    operation: impl FnOnce() -> Result<T>,
) -> Result<T> {
    let result = operation();
    if result.is_err() && path.exists() {
        let _ = fs_err::remove_dir_all(path);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_identifiers() {
        assert!(validate_identifier("name", "valid-name_123").is_ok());
        assert!(validate_identifier("name", "").is_err());
        assert!(validate_identifier("name", "bad name").is_err());
    }
}
