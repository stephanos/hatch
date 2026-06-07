use anyhow::Result;

pub(crate) fn run() -> Result<()> {
    println!(
        "hatch {} (built: {}, commit: {})",
        current_version(),
        build_time(),
        git_sha()
    );
    Ok(())
}

fn current_version() -> &'static str {
    option_env!("HATCH_VERSION")
        .unwrap_or(env!("CARGO_PKG_VERSION"))
        .trim_start_matches('v')
}

fn build_time() -> &'static str {
    option_env!("HATCH_BUILD_TIME").unwrap_or("unknown")
}

fn git_sha() -> &'static str {
    option_env!("HATCH_GIT_SHA").unwrap_or("unknown")
}
