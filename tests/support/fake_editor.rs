#[derive(Clone, Copy)]
pub enum FakeEditor {
    Noop,
    WorkspaceLog,
}

pub fn script(kind: FakeEditor) -> &'static str {
    match kind {
        FakeEditor::Noop => "#!/bin/sh\nexit 0\n",
        FakeEditor::WorkspaceLog => "#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$HATCH_EDITOR_LOG\"\n",
    }
}
