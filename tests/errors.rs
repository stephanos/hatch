#[path = "support/mod.rs"]
mod support;

use crate::support::TestEnv;
use assert_cmd::Command;
use predicates::prelude::*;

#[test]
fn human_errors_are_printed() {
    let env = TestEnv::empty();
    Command::cargo_bin("hatch")
        .unwrap_or_else(|error| panic!("failed to find hatch test binary: {error}"))
        .args(["project", "new"])
        .env("HATCH_TEST_WORKSPACE_ROOT", &env.workspace)
        .env("CLICOLOR_FORCE", "1")
        .env_remove("NO_COLOR")
        .assert()
        .failure()
        .stderr(predicate::str::starts_with("\x1b[31merror:\x1b[0m "))
        .stderr(predicate::str::contains("required"))
        .stderr(predicate::str::contains("error: error:").not());
}

#[test]
fn runtime_errors_use_red_error_prefix() {
    let env = TestEnv::empty();
    Command::cargo_bin("hatch")
        .unwrap_or_else(|error| panic!("failed to find hatch test binary: {error}"))
        .args(["task", "open", "nope"])
        .env("HATCH_TEST_WORKSPACE_ROOT", &env.workspace)
        .env("CLICOLOR_FORCE", "1")
        .env_remove("NO_COLOR")
        .assert()
        .failure()
        .stderr(predicate::str::starts_with("\x1b[31merror:\x1b[0m "))
        .stderr(predicate::str::contains("no task matches: nope"))
        .stderr(predicate::str::contains("hatch: ").not());
}
