use fs_err as fs;
use std::fs::Permissions;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, Output, Stdio};

use tempfile::TempDir;

const PAYLOAD: &str = "#!/bin/sh\nprintf 'hatch fixture\\n'\n";

const ASSETS: &[&str] = &[
    "hatch-aarch64-apple-darwin.tar.gz",
    "hatch-aarch64-unknown-linux-gnu",
    "hatch-x86_64-unknown-linux-gnu",
];

#[test]
fn installs_release_assets_for_supported_platforms() {
    for (os, arch, asset) in [
        ("Darwin", "arm64", ASSETS[0]),
        ("Darwin", "aarch64", ASSETS[0]),
        ("Linux", "arm64", ASSETS[1]),
        ("Linux", "aarch64", ASSETS[1]),
        ("Linux", "x86_64", ASSETS[2]),
        ("Linux", "amd64", ASSETS[2]),
        ("Darwin", "arm64", "hatch-macos-arm64.tar.gz"),
        ("Linux", "amd64", "hatch-linux-amd64"),
    ] {
        let assets = if ASSETS.contains(&asset) {
            ASSETS.to_vec()
        } else {
            vec![asset]
        };
        let installer = Installer::new(&assets);
        let output = installer.run(os, arch);
        assert!(
            output.status.success(),
            "{os}/{arch}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(
            fs::read_to_string(installer.temp.path().join("installed/hatch")).unwrap(),
            PAYLOAD
        );
        assert_eq!(
            fs::read_to_string(installer.temp.path().join("download.log")).unwrap(),
            format!("https://example.com/{asset}\n")
        );
        let installed = Command::new(installer.temp.path().join("installed/hatch"))
            .output()
            .unwrap();
        assert!(installed.status.success());
        assert_eq!(installed.stdout, b"hatch fixture\n");
    }
}

#[test]
fn lists_available_downloads_when_no_asset_matches() {
    let installer = Installer::new(ASSETS);
    let output = installer.run("Darwin", "x86_64");
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("could not find matching release artifact for darwin/x86_64"));
    for asset in ASSETS {
        assert!(stderr.contains(&format!("https://example.com/{asset}")));
    }
    assert!(!installer.temp.path().join("installed/hatch").exists());
}

#[test]
fn rejects_unsupported_architectures() {
    let installer = Installer::new(ASSETS);
    let output = installer.run("Linux", "riscv64");
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unsupported architecture: riscv64"));
    assert!(!installer.temp.path().join("installed/hatch").exists());
}

struct Installer {
    temp: TempDir,
}

impl Installer {
    fn new(assets: &[&str]) -> Self {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        fs::create_dir(root.join("bin")).unwrap();
        fs::create_dir(root.join("payload")).unwrap();
        fs::write(root.join("payload/hatch"), PAYLOAD).unwrap();
        let status = Command::new("tar")
            .arg("-czf")
            .arg(root.join("archive.tar.gz"))
            .arg("-C")
            .arg(root.join("payload"))
            .arg("hatch")
            .status()
            .unwrap();
        assert!(status.success());
        let assets: Vec<_> = assets
            .iter()
            .map(|asset| serde_json::json!({"browser_download_url": format!("https://example.com/{asset}")}))
            .collect();
        fs::write(
            root.join("release.json"),
            serde_json::to_string(&serde_json::json!({"assets": assets})).unwrap(),
        )
        .unwrap();
        for (name, script) in [
            (
                "uname",
                "#!/bin/sh\ncase \"$1\" in\n-s) printf '%s\\n' \"$HATCH_TEST_OS\" ;;\n-m) printf '%s\\n' \"$HATCH_TEST_ARCH\" ;;\nesac\n",
            ),
            (
                "curl",
                r#"#!/bin/sh
set -eu
url="$2"
destination="$4"
case "$url" in
  https://api.github.com/repos/stephanos/hatch/releases/latest)
    cp "$HATCH_TEST_ROOT/release.json" "$destination"
    ;;
  https://example.com/*)
    printf '%s\n' "$url" >> "$HATCH_TEST_ROOT/download.log"
    case "$url" in
      *.tar.gz) cp "$HATCH_TEST_ROOT/archive.tar.gz" "$destination" ;;
      *) cp "$HATCH_TEST_ROOT/payload/hatch" "$destination" ;;
    esac
    ;;
  *) exit 1 ;;
esac
"#,
            ),
        ] {
            let script_path = root.join("bin").join(name);
            fs::write(&script_path, script).unwrap();
            fs::set_permissions(&script_path, Permissions::from_mode(0o755)).unwrap();
        }
        Self { temp }
    }

    fn run(&self, os: &str, arch: &str) -> Output {
        let mut paths = vec![self.temp.path().join("bin")];
        paths.extend(std::env::split_paths(
            &std::env::var_os("PATH").unwrap_or_default(),
        ));
        let mut child = Command::new("sh")
            .env("PATH", std::env::join_paths(paths).unwrap())
            .env("HATCH_TEST_ROOT", self.temp.path())
            .env("HATCH_TEST_OS", os)
            .env("HATCH_TEST_ARCH", arch)
            .env("HATCH_REPO", "stephanos/hatch")
            .env("HATCH_INSTALL_DIR", self.temp.path().join("installed"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(include_bytes!("../install.sh"))
            .unwrap();
        child.wait_with_output().unwrap()
    }
}
