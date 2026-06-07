use anyhow::Context;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use super::AgentProfile;

const JSON_LIMIT_BYTES: u64 = 2 * 1024 * 1024;
const BUNDLE_LIMIT_BYTES: u64 = 8 * 1024 * 1024;
const ARTIFACT_LIMIT_BYTES: u64 = 64 * 1024 * 1024;
const CACHE_REFRESH_SECS: u64 = 24 * 60 * 60;
const CACHE_REFRESH_MARKER: &str = ".hatch-refreshed-at";

#[derive(Debug, Clone)]
struct PackageRef {
    namespace: String,
    name: String,
    version: Option<String>,
}

impl PackageRef {
    fn parse(value: &str) -> anyhow::Result<Self> {
        let (path, version) = value
            .split_once('@')
            .map_or((value, None), |(path, version)| (path, Some(version)));
        let (namespace, name) = path
            .split_once('/')
            .ok_or_else(|| anyhow::anyhow!("profile must be a registry ref: {value}"))?;
        if namespace.is_empty() || name.is_empty() {
            return Err(anyhow::anyhow!("profile must be a registry ref: {value}"));
        }
        Ok(Self {
            namespace: namespace.to_string(),
            name: name.to_string(),
            version: version.map(ToString::to_string),
        })
    }

    fn key(&self) -> String {
        format!("{}/{}", self.namespace, self.name)
    }
}

#[derive(Debug, Deserialize)]
struct PullResponse {
    namespace: String,
    name: String,
    version: String,
    artifacts: Vec<PullArtifact>,
    bundle_url: String,
}

#[derive(Debug, Deserialize)]
struct PullArtifact {
    filename: String,
    sha256_digest: String,
    download_url: String,
}

#[derive(Debug, Deserialize)]
struct PackageManifest {
    #[serde(default)]
    artifacts: Vec<ArtifactEntry>,
}

#[derive(Debug, Deserialize)]
struct ArtifactEntry {
    #[serde(rename = "type")]
    artifact_type: ArtifactType,
    path: String,
    #[serde(default)]
    install_as: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
enum ArtifactType {
    Profile,
    Instruction,
    TrustPolicy,
    Groups,
    Plugin,
}

#[derive(Debug)]
struct DownloadedArtifact {
    filename: String,
    path: PathBuf,
    sha256_digest: String,
}

pub(super) fn load_registry_profile(
    profile: &str,
    cache_dir: &Path,
    registry_url: &str,
) -> anyhow::Result<AgentProfile> {
    let package_ref = PackageRef::parse(profile)?;
    let cached = CachedPackage::new(cache_dir, package_ref);
    cached.ensure(registry_url)?;
    cached.load_profile()
}

#[derive(Debug, Clone)]
struct CachedPackage {
    package_ref: PackageRef,
    cache_dir: PathBuf,
    path: PathBuf,
}

impl CachedPackage {
    fn new(cache_dir: &Path, package_ref: PackageRef) -> Self {
        let path = package_dir(cache_dir, &package_ref);
        Self {
            package_ref,
            cache_dir: cache_dir.to_path_buf(),
            path,
        }
    }

    fn ensure(&self, registry_url: &str) -> anyhow::Result<()> {
        if self.is_installed() && self.is_fresh(current_unix_secs()?) {
            return Ok(());
        }

        if self.is_installed() {
            return refresh_package(&self.package_ref, &self.cache_dir, registry_url).or(Ok(()));
        }

        refresh_package(&self.package_ref, &self.cache_dir, registry_url)
    }

    fn load_profile(&self) -> anyhow::Result<AgentProfile> {
        load_package_profile(&self.package_ref, &self.path)
    }

    fn is_installed(&self) -> bool {
        self.path.join("package.json").is_file()
    }

    fn is_fresh(&self, now_secs: u64) -> bool {
        cached_package_is_fresh(&self.path, now_secs)
    }
}

fn refresh_package(
    package_ref: &PackageRef,
    cache_dir: &Path,
    registry_url: &str,
) -> anyhow::Result<()> {
    let package_dir = package_dir(cache_dir, package_ref);
    let staging = cache_dir
        .join(".staging")
        .join(&package_ref.namespace)
        .join(format!("{}-{}", package_ref.name, std::process::id()));
    if staging.exists() {
        fs_err::remove_dir_all(&staging)
            .with_context(|| format!("failed to clear staging dir {}", staging.display()))?;
    }
    fs_err::create_dir_all(&staging)
        .with_context(|| format!("failed to create staging dir {}", staging.display()))?;

    let client = RegistryClient::new(registry_url);
    let version = package_ref.version.as_deref().unwrap_or("latest");
    let pull = client.fetch_pull_response(package_ref, version)?;
    validate_pull_response(package_ref, &pull)?;
    let downloads = download_and_verify(&client, package_ref, &pull, &staging)?;
    install_package_cache(&staging, &package_dir, &downloads)?;
    Ok(())
}

fn validate_pull_response(package_ref: &PackageRef, pull: &PullResponse) -> anyhow::Result<()> {
    if pull.namespace != package_ref.namespace || pull.name != package_ref.name {
        return Err(anyhow::anyhow!(
            "registry returned {}/{} for requested package {}",
            pull.namespace,
            pull.name,
            package_ref.key()
        ));
    }
    Ok(())
}

fn download_and_verify(
    client: &RegistryClient,
    package_ref: &PackageRef,
    pull: &PullResponse,
    staging: &Path,
) -> anyhow::Result<Vec<DownloadedArtifact>> {
    if pull.artifacts.is_empty() {
        return Err(anyhow::anyhow!(
            "registry package {}@{} did not include artifacts",
            package_ref.key(),
            pull.version
        ));
    }
    let bundle_json = client.download_string(&pull.bundle_url, BUNDLE_LIMIT_BYTES)?;
    let bundle_path = Path::new(".nono-trust.bundle");
    let bundle = nono::trust::load_bundle_from_str(&bundle_json, bundle_path)
        .context("failed to load nono trust bundle")?;
    let subjects = nono::trust::extract_all_subjects(&bundle, bundle_path)
        .context("failed to read nono trust bundle subjects")?;
    let subject_digests = subjects
        .iter()
        .map(|(name, digest)| (digest.as_str(), name.as_str()))
        .collect::<HashMap<_, _>>();
    let Some((_, first_digest)) = subjects.first() else {
        return Err(anyhow::anyhow!("nono trust bundle contains no subjects"));
    };
    let trusted_root = nono::trust::load_production_trusted_root()
        .context("failed to load nono production trusted root")?;
    let policy = nono::trust::VerificationPolicy::default();
    nono::trust::verify_bundle_with_digest(
        first_digest,
        &bundle,
        &trusted_root,
        &policy,
        bundle_path,
    )
    .context("failed to verify nono trust bundle")?;
    let signer_identity = nono::trust::extract_signer_identity(&bundle, bundle_path)
        .context("failed to extract nono trust bundle signer")?;
    enforce_namespace_assertion(package_ref, &signer_identity)?;

    let download_dir = staging.join("downloads");
    fs_err::create_dir_all(&download_dir)
        .with_context(|| format!("failed to create {}", download_dir.display()))?;
    let mut downloads = Vec::with_capacity(pull.artifacts.len());
    for artifact in &pull.artifacts {
        let path = download_dir.join(&artifact.filename);
        validate_relative_path(&artifact.filename)?;
        let digest = client.download_file(&artifact.download_url, &path)?;
        if digest != artifact.sha256_digest {
            return Err(anyhow::anyhow!(
                "artifact {} digest mismatch: registry={}, local={digest}",
                artifact.filename,
                artifact.sha256_digest
            ));
        }
        if !subject_digests.contains_key(digest.as_str()) {
            return Err(anyhow::anyhow!(
                "artifact {} digest not found in nono trust bundle",
                artifact.filename
            ));
        }
        downloads.push(DownloadedArtifact {
            filename: artifact.filename.clone(),
            path,
            sha256_digest: digest,
        });
    }
    fs_err::write(staging.join(".nono-trust.bundle"), bundle_json)
        .with_context(|| format!("failed to write trust bundle in {}", staging.display()))?;
    Ok(downloads)
}

fn enforce_namespace_assertion(
    package_ref: &PackageRef,
    signer_identity: &nono::SignerIdentity,
) -> anyhow::Result<()> {
    match signer_identity {
        nono::SignerIdentity::Keyless { repository, .. } => {
            let signer_namespace = repository.split('/').next().unwrap_or_default();
            if signer_namespace != package_ref.namespace {
                return Err(anyhow::anyhow!(
                    "signer namespace {signer_namespace:?} does not match requested namespace {:?}",
                    package_ref.namespace
                ));
            }
            Ok(())
        }
        nono::SignerIdentity::Keyed { .. } => Err(anyhow::anyhow!(
            "registry packages must use keyless Sigstore signing"
        )),
    }
}

fn install_package_cache(
    staging: &Path,
    package_dir: &Path,
    downloads: &[DownloadedArtifact],
) -> anyhow::Result<()> {
    let manifest_artifact = downloads
        .iter()
        .find(|artifact| artifact.filename == "package.json")
        .ok_or_else(|| anyhow::anyhow!("registry package is missing package.json"))?;
    let manifest_data = fs_err::read_to_string(&manifest_artifact.path)
        .with_context(|| format!("failed to read {}", manifest_artifact.path.display()))?;
    let manifest: PackageManifest =
        serde_json::from_str(&manifest_data).context("failed to parse package.json")?;
    let downloaded_by_name = downloads
        .iter()
        .map(|artifact| (artifact.filename.as_str(), artifact))
        .collect::<HashMap<_, _>>();

    let cache_root = staging.join("package");
    fs_err::create_dir_all(cache_root.join("artifacts"))
        .with_context(|| format!("failed to create {}", cache_root.display()))?;
    fs_err::copy(&manifest_artifact.path, cache_root.join("package.json"))
        .context("failed to stage package manifest")?;
    fs_err::copy(
        staging.join(".nono-trust.bundle"),
        cache_root.join(".nono-trust.bundle"),
    )
    .context("failed to stage trust bundle")?;
    let profile_dir = cache_root.join("profiles");
    fs_err::create_dir_all(&profile_dir)
        .with_context(|| format!("failed to create {}", profile_dir.display()))?;

    for artifact in &manifest.artifacts {
        let downloaded = downloaded_by_name
            .get(artifact.path.as_str())
            .ok_or_else(|| {
                anyhow::anyhow!("package manifest references missing {}", artifact.path)
            })?;
        let artifact_path = cache_root.join("artifacts").join(&artifact.path);
        if let Some(parent) = artifact_path.parent() {
            fs_err::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        fs_err::copy(&downloaded.path, &artifact_path)
            .with_context(|| format!("failed to cache {}", artifact.path))?;
        if artifact.artifact_type == ArtifactType::Profile {
            let install_as = artifact.install_as.as_deref().unwrap_or(&artifact.path);
            let profile_path = profile_dir.join(format!("{install_as}.json"));
            fs_err::copy(&downloaded.path, &profile_path)
                .with_context(|| format!("failed to install profile {}", profile_path.display()))?;
        }
    }

    fs_err::write(
        cache_root.join(".hatch-artifacts.json"),
        serde_json::to_string_pretty(
            &downloads
                .iter()
                .map(|artifact| {
                    serde_json::json!({
                        "filename": artifact.filename,
                        "sha256_digest": artifact.sha256_digest,
                    })
                })
                .collect::<Vec<_>>(),
        )?,
    )
    .context("failed to write artifact digest cache")?;

    if let Some(parent) = package_dir.parent() {
        fs_err::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    if package_dir.exists() {
        fs_err::remove_dir_all(package_dir)
            .with_context(|| format!("failed to replace {}", package_dir.display()))?;
    }
    write_refresh_marker(&cache_root)?;
    fs_err::rename(cache_root, package_dir)
        .with_context(|| format!("failed to install {}", package_dir.display()))
}

fn load_package_profile(
    package_ref: &PackageRef,
    package_dir: &Path,
) -> anyhow::Result<AgentProfile> {
    let manifest_data = fs_err::read_to_string(package_dir.join("package.json"))
        .with_context(|| format!("failed to read package cache for {}", package_ref.key()))?;
    let manifest: PackageManifest =
        serde_json::from_str(&manifest_data).context("failed to parse cached package manifest")?;
    let profile = manifest
        .artifacts
        .iter()
        .find(|artifact| artifact.artifact_type == ArtifactType::Profile)
        .ok_or_else(|| anyhow::anyhow!("package {} has no profile artifact", package_ref.key()))?;
    let install_as = profile.install_as.as_deref().unwrap_or(&profile.path);
    super::load_profile_path(
        &package_dir
            .join("profiles")
            .join(format!("{install_as}.json")),
    )
}

fn package_dir(cache_dir: &Path, package_ref: &PackageRef) -> PathBuf {
    cache_dir
        .join("packages")
        .join(&package_ref.namespace)
        .join(&package_ref.name)
}

fn cached_package_is_fresh(package_dir: &Path, now_secs: u64) -> bool {
    let Ok(data) = fs_err::read_to_string(package_dir.join(CACHE_REFRESH_MARKER)) else {
        return false;
    };
    let Ok(refreshed_at) = data.trim().parse::<u64>() else {
        return false;
    };
    now_secs.saturating_sub(refreshed_at) < CACHE_REFRESH_SECS
}

fn write_refresh_marker(package_dir: &Path) -> anyhow::Result<()> {
    fs_err::write(
        package_dir.join(CACHE_REFRESH_MARKER),
        format!("{}\n", current_unix_secs()?),
    )
    .with_context(|| {
        format!(
            "failed to write refresh marker in {}",
            package_dir.display()
        )
    })
}

fn current_unix_secs() -> anyhow::Result<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before UNIX epoch")?
        .as_secs())
}

fn validate_relative_path(value: &str) -> anyhow::Result<()> {
    let path = Path::new(value);
    if path.is_absolute()
        || path
            .components()
            .any(|component| component.as_os_str() == "..")
    {
        return Err(anyhow::anyhow!("registry artifact path is unsafe: {value}"));
    }
    Ok(())
}

struct RegistryClient {
    base_url: String,
    http: ureq::Agent,
}

impl RegistryClient {
    fn new(base_url: &str) -> Self {
        let tls_config = ureq::tls::TlsConfig::builder()
            .root_certs(ureq::tls::RootCerts::PlatformVerifier)
            .build();
        let http = ureq::Agent::config_builder()
            .tls_config(tls_config)
            .build()
            .new_agent();
        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            http,
        }
    }

    fn fetch_pull_response(
        &self,
        package_ref: &PackageRef,
        version: &str,
    ) -> anyhow::Result<PullResponse> {
        self.get_json(&format!(
            "/api/v1/packages/{}/{}/versions/{version}/pull",
            package_ref.namespace, package_ref.name
        ))
    }

    fn get_json<T: serde::de::DeserializeOwned>(&self, path: &str) -> anyhow::Result<T> {
        let body = self.download_string(path, JSON_LIMIT_BYTES)?;
        serde_json::from_str(&body).context("failed to decode registry JSON")
    }

    fn download_string(&self, url: &str, limit: u64) -> anyhow::Result<String> {
        let url = self.resolve_url(url);
        let mut response = self.http.get(&url).call()?;
        enforce_content_length(response.body().content_length(), limit, &url)?;
        response
            .body_mut()
            .with_config()
            .limit(limit)
            .read_to_string()
            .with_context(|| format!("failed to read registry response from {url}"))
    }

    fn download_file(&self, url: &str, dest: &Path) -> anyhow::Result<String> {
        let url = self.resolve_url(url);
        let mut response = self.http.get(&url).call()?;
        enforce_content_length(response.body().content_length(), ARTIFACT_LIMIT_BYTES, &url)?;
        if let Some(parent) = dest.parent() {
            fs_err::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        let mut reader = response
            .body_mut()
            .with_config()
            .limit(ARTIFACT_LIMIT_BYTES)
            .reader();
        let mut file = fs_err::File::create(dest)
            .with_context(|| format!("failed to create {}", dest.display()))?;
        let mut hasher = Sha256::new();
        let mut buffer = [0_u8; 8192];
        loop {
            let read = reader
                .read(&mut buffer)
                .with_context(|| format!("failed to read registry response from {url}"))?;
            if read == 0 {
                break;
            }
            file.write_all(&buffer[..read])
                .with_context(|| format!("failed to write {}", dest.display()))?;
            hasher.update(&buffer[..read]);
        }
        Ok(format_digest(hasher.finalize().as_slice()))
    }

    fn resolve_url(&self, url: &str) -> String {
        if url.starts_with("https://") || url.starts_with("http://") {
            url.to_string()
        } else {
            format!("{}{}", self.base_url, url)
        }
    }
}

fn enforce_content_length(length: Option<u64>, limit: u64, url: &str) -> anyhow::Result<()> {
    if let Some(length) = length
        && length > limit
    {
        return Err(anyhow::anyhow!(
            "registry response from {url} exceeds {limit} bytes"
        ));
    }
    Ok(())
}

fn format_digest(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cached_package_is_fresh_for_less_than_twenty_four_hours() {
        let temp =
            tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let package_dir = temp.path().join("package");
        fs_err::create_dir_all(&package_dir)
            .unwrap_or_else(|error| panic!("failed to create package dir: {error}"));
        fs_err::write(package_dir.join(CACHE_REFRESH_MARKER), "100\n")
            .unwrap_or_else(|error| panic!("failed to write refresh marker: {error}"));

        assert!(cached_package_is_fresh(
            &package_dir,
            100 + CACHE_REFRESH_SECS - 1
        ));
        assert!(!cached_package_is_fresh(
            &package_dir,
            100 + CACHE_REFRESH_SECS
        ));
    }

    #[test]
    fn cached_package_without_valid_marker_is_stale() {
        let temp =
            tempfile::tempdir().unwrap_or_else(|error| panic!("failed to create tempdir: {error}"));
        let package_dir = temp.path().join("package");
        fs_err::create_dir_all(&package_dir)
            .unwrap_or_else(|error| panic!("failed to create package dir: {error}"));

        assert!(!cached_package_is_fresh(&package_dir, 100));

        fs_err::write(package_dir.join(CACHE_REFRESH_MARKER), "not-a-timestamp\n")
            .unwrap_or_else(|error| panic!("failed to write refresh marker: {error}"));

        assert!(!cached_package_is_fresh(&package_dir, 100));
    }
}
