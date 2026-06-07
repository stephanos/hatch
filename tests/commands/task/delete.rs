use crate::support::TestEnv;

#[test]
fn task_delete_removes_unambiguous_task() {
    let env = TestEnv::configured();
    let task = env.path("api/setup-ci");
    env.mkdir("api/setup-ci");
    env.mkdir("api/.hatch");

    let deleted = env.run_stdout(&["task", "delete", "setup"]);
    assert_eq!(deleted.trim(), env.path("api/setup-ci").to_string_lossy());
    assert!(!task.exists());
}
