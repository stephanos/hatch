use crate::Result;
use crate::process::ProcessRunner;
use camino::Utf8Path;

#[derive(Debug, Default, Clone)]
pub(crate) struct GithubCli {
    runner: ProcessRunner,
}

impl GithubCli {
    pub(crate) fn pull_request_head_ref(&self, pr_url: &str) -> Result<String> {
        self.runner.run(
            "gh",
            &[
                "pr".to_string(),
                "view".to_string(),
                pr_url.to_string(),
                "--json".to_string(),
                "headRefName".to_string(),
                "--jq".to_string(),
                ".headRefName".to_string(),
            ],
            None,
            None,
        )
    }

    pub(crate) fn pull_request_cleanup_reason(
        &self,
        repo_path: &Utf8Path,
        branch: &str,
    ) -> Result<String> {
        self.runner.run(
            "gh",
            &[
                "pr".to_string(),
                "view".to_string(),
                branch.to_string(),
                "--json".to_string(),
                "state,mergedAt".to_string(),
                "--jq".to_string(),
                "if .mergedAt != null then \"MERGED\" elif .state == \"CLOSED\" then \"CLOSED\" else \"\" end"
                    .to_string(),
            ],
            Some(repo_path),
            None,
        )
    }

    pub(crate) fn pull_request_state(&self, repo_path: &Utf8Path, branch: &str) -> Result<String> {
        self.runner.run(
            "gh",
            &[
                "pr".to_string(),
                "view".to_string(),
                branch.to_string(),
                "--json".to_string(),
                "state".to_string(),
                "--jq".to_string(),
                ".state".to_string(),
            ],
            Some(repo_path),
            None,
        )
    }
}
