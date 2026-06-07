use crate::support::TestEnv;

#[test]
fn task_list_prints_tasks() {
    let env = TestEnv::configured();
    env.mkdir("api/task-one");
    env.mkdir("api/.hatch");

    let tasks = env.run_stdout(&["task", "list"]);
    assert_eq!(tasks.trim(), "api/task-one");
}
