use crate::discovery::WorkspaceDiscovery;
use crate::git::GitCli;
use crate::{Error, Result};
use camino::Utf8Path;
use std::collections::BTreeSet;
use url::Url;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepoSpec {
    pub repo: String,
    pub clone_url: String,
}

const DEFAULT_GITHUB_HOST: &str = "github.com";

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct RepoNamespace {
    namespace: String,
}

#[derive(Debug, Default, Clone)]
pub struct RepoService {
    discovery: WorkspaceDiscovery,
    git: GitCli,
}

struct RemoteDetails {
    repo: String,
    clone_url: String,
    namespace: Option<RepoNamespace>,
}

impl RepoService {
    pub fn resolve_repo_spec_from_task(
        &self,
        repo_input: &str,
        task_path: &Utf8Path,
    ) -> Result<RepoSpec> {
        self.resolve_repo_spec_with_namespace(repo_input, || self.infer_repo_namespace(task_path))
    }

    fn resolve_repo_spec_with_namespace(
        &self,
        repo_input: &str,
        namespace_provider: impl FnOnce() -> Result<RepoNamespace>,
    ) -> Result<RepoSpec> {
        let trimmed = repo_input.trim();
        if trimmed.is_empty() {
            return Err(Error::Message("repo cannot be empty".to_string()));
        }
        if trimmed.starts_with("http://")
            || trimmed.starts_with("https://")
            || trimmed.starts_with("git@")
            || trimmed.starts_with("file://")
        {
            let Some(remote) = remote_details(trimmed) else {
                return Err(Error::Message(
                    "repo must be a name, org/repo, or clone URL".to_string(),
                ));
            };
            if !remote.clone_url.starts_with("file://") && remote.namespace.is_none() {
                return Err(Error::Message(
                    "only github.com repository URLs are supported".to_string(),
                ));
            }
            return Ok(RepoSpec {
                repo: remote.repo,
                clone_url: remote.clone_url,
            });
        }
        if let Some((org, repo)) = trimmed.split_once('/') {
            let org = org.trim();
            let repo = repo.trim();
            if org.is_empty() || repo.is_empty() || repo.contains('/') {
                return Err(Error::Message(
                    "repo must be a name, org/repo, or clone URL".to_string(),
                ));
            }
            return Ok(RepoSpec {
                repo: repo.to_string(),
                clone_url: format!("https://{}/{}/{repo}.git", DEFAULT_GITHUB_HOST, org),
            });
        }
        let namespace = namespace_provider()?;
        Ok(RepoSpec {
            repo: trimmed.to_string(),
            clone_url: format!(
                "https://{}/{}/{}.git",
                DEFAULT_GITHUB_HOST, namespace.namespace, trimmed
            ),
        })
    }

    fn infer_repo_namespace(&self, task_path: &Utf8Path) -> Result<RepoNamespace> {
        let mut namespaces = BTreeSet::new();
        let mut has_non_github_remote = false;
        for repo in self.discovery.list_task_repos(task_path)? {
            let Ok(origin) = self.git.origin_url(&repo.path) else {
                continue;
            };
            if let Some(namespace) = repo_namespace_from_remote(origin.trim()) {
                namespaces.insert(namespace);
            } else if !origin.trim().is_empty() {
                has_non_github_remote = true;
            }
        }
        if has_non_github_remote {
            return Err(Error::Message(
                "Task repos include non-GitHub URLs; use explicit GitHub URLs".to_string(),
            ));
        }
        match namespaces.len() {
            1 => Ok(namespaces.into_iter().next().unwrap()),
            0 => Err(Error::Message(
                "Could not infer repo namespace from task repos; specify org/repo or a GitHub clone URL"
                    .to_string(),
            )),
            _ => Err(Error::Message(
                "Task repos use multiple GitHub namespaces; specify a clone URL".to_string(),
            )),
        }
    }
}

fn repo_namespace_from_remote(remote: &str) -> Option<RepoNamespace> {
    remote_details(remote).and_then(|remote| remote.namespace)
}

fn remote_details(remote: &str) -> Option<RemoteDetails> {
    let without_fragment = remote
        .split_once('#')
        .map_or(remote, |(without_fragment, _)| without_fragment);
    if let Some(rest) = without_fragment.strip_prefix("git@") {
        let (host, path) = rest.split_once(':')?;
        return remote_details_from_host_and_path(host, path, without_fragment.to_string());
    }

    let mut url = Url::parse(without_fragment).ok()?;
    url.set_fragment(None);
    match url.scheme() {
        "file" => {
            let repo = repo_name_from_path(url.path())?;
            Some(RemoteDetails {
                repo,
                clone_url: url.to_string(),
                namespace: None,
            })
        }
        "http" | "https" => remote_details_from_url(&url),
        "ssh" if url.username() == "git" => remote_details_from_url(&url),
        _ => None,
    }
}

fn remote_details_from_url(url: &Url) -> Option<RemoteDetails> {
    let host = url.host_str()?;
    remote_details_from_host_and_path(host, url.path(), url.to_string())
}

fn remote_details_from_host_and_path(
    host: &str,
    path: &str,
    clone_url: String,
) -> Option<RemoteDetails> {
    let repo = repo_name_from_path(path)?;
    let namespace = namespace_from_host_and_path(host, path);
    Some(RemoteDetails {
        repo,
        clone_url,
        namespace,
    })
}

fn repo_name_from_path(path: &str) -> Option<String> {
    let repo = path
        .trim_end_matches('/')
        .strip_suffix(".git")
        .unwrap_or_else(|| path.trim_end_matches('/'))
        .split('/')
        .rfind(|part| !part.is_empty())?;
    if repo.is_empty() {
        None
    } else {
        Some(repo.to_string())
    }
}

fn namespace_from_host_and_path(host: &str, path: &str) -> Option<RepoNamespace> {
    if host != DEFAULT_GITHUB_HOST {
        return None;
    }
    let parts = path
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let repo = parts.last()?;
    if host.is_empty() || repo.is_empty() || parts.len() < 2 {
        return None;
    }
    Some(RepoNamespace {
        namespace: parts[..parts.len() - 1].join("/"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_explicit_org_repo() {
        let service = RepoService::default();
        let temp = tempfile::tempdir().unwrap();
        let task_path = camino::Utf8PathBuf::from_path_buf(temp.path().to_path_buf()).unwrap();

        let spec = service
            .resolve_repo_spec_from_task("acme/web", &task_path)
            .expect("expected org/repo to resolve");

        assert_eq!(spec.repo, "web");
        assert_eq!(spec.clone_url, "https://github.com/acme/web.git");
    }

    #[test]
    fn rejects_bare_repo_without_namespace() {
        let service = RepoService::default();
        let temp = tempfile::tempdir().unwrap();
        let task_path = camino::Utf8PathBuf::from_path_buf(temp.path().to_path_buf()).unwrap();

        let error = service
            .resolve_repo_spec_from_task("web", &task_path)
            .unwrap_err();

        assert!(error.to_string().contains("Could not infer repo namespace"));
    }

    #[test]
    fn resolves_file_url() {
        let service = RepoService::default();
        let temp = tempfile::tempdir().unwrap();
        let task_path = camino::Utf8PathBuf::from_path_buf(temp.path().to_path_buf()).unwrap();

        let spec = service
            .resolve_repo_spec_from_task("file:///tmp/hatch-fixture/api.git", &task_path)
            .expect("expected file URL to resolve");

        assert_eq!(spec.repo, "api");
        assert_eq!(spec.clone_url, "file:///tmp/hatch-fixture/api.git");
    }

    #[test]
    fn parses_repo_namespace_from_supported_remotes() {
        assert_eq!(
            repo_namespace_from_remote("https://github.com/acme/api.git"),
            Some(RepoNamespace {
                namespace: "acme".to_string()
            })
        );
        assert_eq!(
            repo_namespace_from_remote("git@github.com:acme/api.git"),
            Some(RepoNamespace {
                namespace: "acme".to_string()
            })
        );
        assert_eq!(
            repo_namespace_from_remote("ssh://git@github.com/acme/api.git"),
            Some(RepoNamespace {
                namespace: "acme".to_string()
            })
        );
        assert_eq!(
            repo_namespace_from_remote("https://gitlab.com/group/subgroup/api.git"),
            None
        );
    }
}
