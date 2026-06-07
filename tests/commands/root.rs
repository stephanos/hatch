use crate::support::env::TestEnv;

#[test]
fn root_without_workspace_prints_setup_prompt() {
    let env = TestEnv::empty();

    let output = env.run_output_with_env(
        &[],
        None,
        &[(
            "HATCH_TEST_WORKSPACE_ROOT",
            env.workspace.display().to_string(),
        )],
    );
    let stdout = String::from_utf8_lossy(&output.stdout);

    assert!(
        stdout.contains("\u{1b}[33m"),
        "expected yellow prompt, got: {stdout:?}"
    );
    assert!(stdout.contains("No hatch workspace found"));
    assert!(stdout.contains("hatch workspace new"));
    assert!(stdout.contains(&env.workspace.display().to_string()));
    assert!(!stdout.contains("Usage: hatch <COMMAND>"));
}

#[test]
fn root_with_workspace_prints_help_with_workspace_path() {
    let env = TestEnv::configured();

    let output = env.run_output(&[], None);
    let stdout = String::from_utf8_lossy(&output.stdout);

    assert!(stdout.contains("Usage: hatch [COMMAND]"));
    assert!(stdout.contains("Workspace:"));
    assert!(stdout.contains(&env.workspace.display().to_string()));
    assert!(stdout.ends_with("\n\n"));
    assert!(!stdout.contains("No hatch workspace found"));
}

#[test]
fn root_help_with_workspace_prints_workspace_path() {
    let env = TestEnv::configured();

    let output = env.run_output(&["--help"], None);
    let stdout = String::from_utf8_lossy(&output.stdout);

    assert!(stdout.contains("Usage: hatch [COMMAND]"));
    assert!(stdout.contains("Workspace:"));
    assert!(stdout.contains(&env.workspace.display().to_string()));
    assert!(stdout.ends_with("\n\n"));
}
