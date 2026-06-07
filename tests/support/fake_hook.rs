#[derive(Clone, Copy)]
pub enum FakeHook {
    TaskOpenProjectLog,
    TaskOpenWorkspaceLog,
}

pub fn script(kind: FakeHook) -> &'static str {
    match kind {
        FakeHook::TaskOpenProjectLog => {
            "#!/bin/sh\nprintf 'project\\n' > \"$HATCH_TASK_OPEN_LOG\"\n"
        }
        FakeHook::TaskOpenWorkspaceLog => {
            "#!/bin/sh\nprintf 'workspace\\n' > \"$HATCH_TASK_OPEN_LOG\"\n"
        }
    }
}
