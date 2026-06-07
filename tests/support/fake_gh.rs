#[derive(Clone, Copy)]
pub enum FakeGh {
    Default,
    Login,
    ClosedPrs,
    PrView,
}

pub fn script(kind: FakeGh) -> &'static str {
    match kind {
        FakeGh::Default => DEFAULT,
        FakeGh::Login => LOGIN,
        FakeGh::ClosedPrs => CLOSED_PRS,
        FakeGh::PrView => PR_VIEW,
    }
}

const DEFAULT: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "gh version 2.45.0"
  exit 0
fi
printf 'unsupported gh invocation: %s\n' "$*" >&2
exit 1
"#;

const LOGIN: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo 'gh version 2.92.0'
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "user" ] && [ "$3" = "--jq" ] && [ "$4" = ".login" ]; then
  printf 'octocat\n'
  exit 0
fi
printf 'unsupported gh invocation: %s\n' "$*" >&2
exit 1
"#;

const CLOSED_PRS: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo 'gh version 2.92.0'
  exit 0
fi
printf 'CLOSED\n'
"#;

const PR_VIEW: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo 'gh version 2.92.0'
  exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "view" ] && [ "$4" = "--json" ] && [ "$5" = "headRefName" ] && [ "$6" = "--jq" ] && [ "$7" = ".headRefName" ]; then
  case "$3" in
    https://github.com/acme/web/pull/123)
      printf 'setup-ci\n'
      exit 0
      ;;
    https://github.com/acme/web/pull/456)
      printf 'feature/stephan/setup-ci\n'
      exit 0
      ;;
    https://github.com/acme/web/pull/999)
      printf 'could not find pull request\n' >&2
      exit 1
      ;;
  esac
fi

printf 'unsupported gh invocation: %s\n' "$*" >&2
exit 1
"#;
