use crate::{Error, Result};
use camino::Utf8Path;
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::thread;

#[derive(Debug, Default, Clone)]
pub struct ProcessRunner;

impl ProcessRunner {
    pub fn run(
        &self,
        program: &str,
        arguments: &[String],
        current_directory: Option<&Utf8Path>,
        environment: Option<&BTreeMap<String, String>>,
    ) -> Result<String> {
        let mut command = Command::new(program);
        command.args(arguments);
        if let Some(current_directory) = current_directory {
            command.current_dir(current_directory);
        }
        if let Some(environment) = environment {
            command.envs(environment);
        }
        let output = command
            .output()
            .map_err(|source| Error::Message(format!("failed to run {program}: {source}")))?;
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if !output.status.success() {
            let message = if stderr.is_empty() { stdout } else { stderr };
            return Err(Error::Message(message));
        }
        Ok(stdout)
    }

    pub fn run_streaming(
        &self,
        program: &str,
        arguments: &[String],
        current_directory: Option<&Utf8Path>,
        environment: Option<&BTreeMap<String, String>>,
    ) -> Result<String> {
        let mut command = Command::new(program);
        command
            .args(arguments)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(current_directory) = current_directory {
            command.current_dir(current_directory);
        }
        if let Some(environment) = environment {
            command.envs(environment);
        }
        let mut child = command
            .spawn()
            .map_err(|source| Error::Message(format!("failed to run {program}: {source}")))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| Error::Message(format!("failed to capture stdout for {program}")))?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| Error::Message(format!("failed to capture stderr for {program}")))?;
        let stdout_thread = thread::spawn(move || stream_output(stdout, std::io::stdout()));
        let stderr_thread = thread::spawn(move || stream_output(stderr, std::io::stderr()));
        let status = child
            .wait()
            .map_err(|source| Error::Message(format!("failed to wait for {program}: {source}")))?;
        let stdout = stdout_thread
            .join()
            .map_err(|_| Error::Message(format!("stdout reader panicked for {program}")))??;
        let stderr = stderr_thread
            .join()
            .map_err(|_| Error::Message(format!("stderr reader panicked for {program}")))??;
        let stdout = String::from_utf8_lossy(&stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&stderr).trim().to_string();
        if !status.success() {
            let message = if stderr.is_empty() {
                stdout
            } else {
                format!("{program} exited with {status}: {stderr}")
            };
            return Err(Error::Message(message));
        }
        Ok(stdout)
    }
}

fn stream_output<R, W>(mut reader: R, mut writer: W) -> Result<Vec<u8>>
where
    R: Read,
    W: Write,
{
    let mut captured = Vec::new();
    let mut buffer = [0; 8192];
    loop {
        let bytes_read = reader
            .read(&mut buffer)
            .map_err(|source| Error::Message(format!("failed to read process output: {source}")))?;
        if bytes_read == 0 {
            break;
        }
        writer.write_all(&buffer[..bytes_read]).map_err(|source| {
            Error::Message(format!("failed to write process output: {source}"))
        })?;
        writer.flush().map_err(|source| {
            Error::Message(format!("failed to flush process output: {source}"))
        })?;
        captured.extend_from_slice(&buffer[..bytes_read]);
    }
    Ok(captured)
}
