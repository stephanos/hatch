use anyhow::Context;
use clap::Parser;
use nono::Sandbox;
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

use super::agent_sandbox::AgentSandboxConfig;

#[derive(Debug, Parser)]
pub struct AgentExecArgs {
    pub(crate) program: String,
    #[arg(long)]
    pub(crate) profile: Vec<String>,
    #[arg(long = "profile-cache")]
    pub(crate) profile_cache: Option<PathBuf>,
    #[arg(long)]
    pub(crate) registry: Option<String>,
    #[arg(long)]
    pub(crate) allow: Vec<PathBuf>,
    #[arg(long)]
    pub(crate) read: Vec<PathBuf>,
    #[arg(long)]
    pub(crate) write: Vec<PathBuf>,
    #[arg(long = "block-net")]
    pub(crate) block_net: bool,
    #[arg(long = "allow-port")]
    pub(crate) allow_port: Vec<u16>,
    #[arg(last = true)]
    pub(crate) args: Vec<String>,
}

impl AgentExecArgs {
    fn sandbox_config(&self) -> AgentSandboxConfig<'_> {
        AgentSandboxConfig {
            profile: &self.profile,
            profile_cache: self.profile_cache.as_deref(),
            registry: self.registry.as_deref(),
            allow: &self.allow,
            read: &self.read,
            write: &self.write,
            block_net: self.block_net,
            allow_port: &self.allow_port,
        }
    }
}

pub(crate) fn run(args: AgentExecArgs) -> anyhow::Result<()> {
    let program = resolve_program(&args.program)?;
    let caps = super::agent_sandbox::build_capabilities(&args.sandbox_config(), &program)?;
    Sandbox::apply(&caps).map_err(|error| anyhow::anyhow!("failed to apply sandbox: {error}"))?;
    exec_program(&program, &args.args)
}

fn resolve_program(program: &str) -> anyhow::Result<PathBuf> {
    let path = Path::new(program);
    if path.components().count() > 1 {
        return fs_err::canonicalize(path)
            .with_context(|| format!("failed to resolve program {program}"));
    }
    let path = env::var_os("PATH")
        .and_then(|paths| {
            env::split_paths(&paths)
                .map(|directory| directory.join(program))
                .find(|candidate| candidate.is_file())
        })
        .ok_or_else(|| anyhow::anyhow!("program not found: {program}"))?;
    fs_err::canonicalize(&path).with_context(|| format!("failed to resolve program {program}"))
}

#[cfg(unix)]
fn exec_program(program: &Path, args: &[String]) -> anyhow::Result<()> {
    use std::os::unix::process::CommandExt;

    let error = Command::new(program).args(args).exec();
    Err(anyhow::anyhow!(
        "failed to exec {}: {error}",
        program.display()
    ))
}

#[cfg(not(unix))]
fn exec_program(program: &Path, args: &[String]) -> anyhow::Result<()> {
    let status = Command::new(program).args(args).status().with_context(|| {
        format!(
            "failed to start sandboxed agent process {}",
            program.display()
        )
    })?;
    if status.success() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(
            "sandboxed agent process {} exited with {status}",
            program.display()
        ))
    }
}
