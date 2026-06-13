use anyhow::Context;
use clap::Parser;
use directories::BaseDirs;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use super::version::current_version;

#[derive(Debug, Parser)]
pub struct UpdateArgs {
    #[arg(long)]
    pub check: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SelfUpdateCache {
    checked_at: u64,
    latest_version: String,
}

const SELF_UPDATE_CACHE_TTL: Duration = Duration::from_secs(12 * 60 * 60);
const SELF_UPDATE_GITHUB_OWNER: &str = "stephanos";
const SELF_UPDATE_GITHUB_REPO: &str = "hatch";
const SELF_UPDATE_GITHUB_REPO_BIN: &str = "hatch";

pub fn run_update(args: UpdateArgs) -> anyhow::Result<()> {
    if args.check {
        let latest = latest_release_version_cached()?;
        let current = current_version();
        if latest == current {
            println!("hatch is up to date ({current})");
            return Ok(());
        }

        println!("Update available: {latest} (current {current})");
        return Ok(());
    }

    let status = perform_self_update()?;
    if status.uptodate() {
        println!("hatch is up to date ({})", status.version());
    } else {
        println!("Updated hatch to {}", status.version());
    }
    cache_self_update_status(status.version())?;
    Ok(())
}

fn latest_release_version_cached() -> anyhow::Result<String> {
    if let Some(cached) = load_self_update_cache()? {
        return Ok(cached);
    }
    let updater = self_update_builder()?;
    let release = updater.get_latest_release()?;
    cache_self_update_status(&release.version)?;
    Ok(release.version)
}

fn perform_self_update() -> anyhow::Result<self_update::Status> {
    let updater = self_update_builder()?;
    Ok(updater.update()?)
}

fn self_update_builder() -> anyhow::Result<Box<dyn self_update::update::ReleaseUpdate>> {
    Ok(self_update::backends::github::Update::configure()
        .repo_owner(SELF_UPDATE_GITHUB_OWNER)
        .repo_name(SELF_UPDATE_GITHUB_REPO)
        .bin_name(SELF_UPDATE_GITHUB_REPO_BIN)
        .show_download_progress(false)
        .current_version(current_version())
        .no_confirm(true)
        .build()?)
}

fn cache_self_update_status(latest_version: &str) -> anyhow::Result<()> {
    let cache = SelfUpdateCache {
        checked_at: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .context("system clock before UNIX epoch")?
            .as_secs(),
        latest_version: latest_version.to_string(),
    };
    let path = self_update_cache_path()?;
    if let Some(parent) = path.parent() {
        fs_err::create_dir_all(parent)?;
    }
    let data = serde_json::to_string_pretty(&cache)?;
    fs_err::write(path, data)?;
    Ok(())
}

fn load_self_update_cache() -> anyhow::Result<Option<String>> {
    let path = self_update_cache_path()?;
    if !path.exists() {
        return Ok(None);
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock before UNIX epoch")?
        .as_secs();
    let data = fs_err::read_to_string(path)?;
    let cache: SelfUpdateCache = match serde_json::from_str(&data) {
        Ok(cache) => cache,
        Err(_) => return Ok(None),
    };
    if now.saturating_sub(cache.checked_at) <= SELF_UPDATE_CACHE_TTL.as_secs() {
        return Ok(Some(cache.latest_version));
    }
    Ok(None)
}

fn self_update_cache_path() -> anyhow::Result<PathBuf> {
    let base = BaseDirs::new()
        .context("could not resolve user cache directory")?
        .cache_dir()
        .to_path_buf();
    Ok(base.join("hatch").join("self-update.json"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn with_cache_home(test: impl FnOnce()) {
        let _guard = ENV_LOCK.lock().unwrap();
        let tempdir = tempfile::tempdir().unwrap();
        let previous_xdg_cache_home = std::env::var_os("XDG_CACHE_HOME");
        let previous_home = std::env::var_os("HOME");
        let previous_localappdata = std::env::var_os("LOCALAPPDATA");
        unsafe {
            std::env::set_var("XDG_CACHE_HOME", tempdir.path());
            std::env::set_var("HOME", tempdir.path());
            std::env::remove_var("LOCALAPPDATA");
        }
        test();
        unsafe {
            match previous_xdg_cache_home {
                Some(value) => std::env::set_var("XDG_CACHE_HOME", value),
                None => std::env::remove_var("XDG_CACHE_HOME"),
            }
            match previous_home {
                Some(value) => std::env::set_var("HOME", value),
                None => std::env::remove_var("HOME"),
            }
            match previous_localappdata {
                Some(value) => std::env::set_var("LOCALAPPDATA", value),
                None => std::env::remove_var("LOCALAPPDATA"),
            }
        }
    }

    #[test]
    fn cache_round_trips_latest_version_inside_ttl() {
        with_cache_home(|| {
            cache_self_update_status("1.2.3").unwrap();
            assert_eq!(load_self_update_cache().unwrap(), Some("1.2.3".to_string()));
        });
    }

    #[test]
    fn cache_ignores_expired_entries() {
        with_cache_home(|| {
            let checked_at = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
                .saturating_sub(SELF_UPDATE_CACHE_TTL.as_secs() + 1);
            let cache = SelfUpdateCache {
                checked_at,
                latest_version: "9.9.9".to_string(),
            };
            let path = self_update_cache_path().unwrap();
            fs_err::create_dir_all(path.parent().unwrap()).unwrap();
            fs_err::write(path, serde_json::to_string(&cache).unwrap()).unwrap();

            assert_eq!(load_self_update_cache().unwrap(), None);
        });
    }

    #[test]
    fn cache_ignores_invalid_json() {
        with_cache_home(|| {
            let path = self_update_cache_path().unwrap();
            fs_err::create_dir_all(path.parent().unwrap()).unwrap();
            fs_err::write(path, "{not json").unwrap();

            assert_eq!(load_self_update_cache().unwrap(), None);
        });
    }
}
