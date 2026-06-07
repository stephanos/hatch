use crate::support::TestEnv;

#[test]
fn version_command_outputs_version() {
    let env = TestEnv::empty();
    let output = env.run_output(&["version"], None);
    env.assert_success(&output);
    let stdout = String::from_utf8_lossy(&output.stdout);
    let version = env!("CARGO_PKG_VERSION").trim_start_matches('v');
    assert!(
        stdout.contains(&format!("hatch {}", version)),
        "stdout: {stdout}"
    );
    assert!(stdout.contains("built: "), "stdout: {stdout}");
    assert!(stdout.contains("commit: "), "stdout: {stdout}");
}
