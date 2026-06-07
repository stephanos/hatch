use std::env;
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

fn main() {
    let build_time = build_timestamp();
    println!("cargo:rustc-env=HATCH_BUILD_TIME={build_time}");

    let git_sha = git_sha().unwrap_or_else(|| "unknown".to_string());
    println!("cargo:rustc-env=HATCH_GIT_SHA={git_sha}");
}

fn build_timestamp() -> String {
    let epoch_seconds = env::var("SOURCE_DATE_EPOCH")
        .ok()
        .and_then(|epoch_value| epoch_value.parse::<u64>().ok());

    if let Some(epoch_seconds) = epoch_seconds {
        return humantime::format_rfc3339(UNIX_EPOCH + Duration::from_secs(epoch_seconds))
            .to_string();
    }

    humantime::format_rfc3339(SystemTime::now()).to_string()
}

fn git_sha() -> Option<String> {
    let output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    String::from_utf8(output.stdout)
        .ok()
        .map(|sha| sha.trim().to_string())
}
