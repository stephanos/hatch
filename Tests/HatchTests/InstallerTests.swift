import Foundation
import HatchCore

let installerTests: [TestCase] = [
  .init(name: "CLI installer creates symlink", run: testCLIInstallerCreatesSymlinkInConfiguredDirectory),
  .init(name: "CLI installer replaces stale symlink", run: testCLIInstallerReplacesStaleSymlink),
  .init(name: "CLI installer expands tilde path", run: testCLIInstallerExpandsTildePath),
  .init(name: "CLI installer locates bundled binary from app bundle", run: testCLIInstallerLocatesBundledBinaryFromAppBundle),
  .init(name: "CLI installer fails when bundled binary missing", run: testCLIInstallerFailsWhenBinaryMissing),
]

func testCLIInstallerCreatesSymlinkInConfiguredDirectory() throws {
  try withTempDirectory { root in
    let macOSDir = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
    let cliBinary = macOSDir.appendingPathComponent("hatch-cli")
    let installDir = root.appendingPathComponent("bin", isDirectory: true)

    try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
    try "#!/bin/sh\n".write(to: cliBinary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliBinary.path)

    let installer = CLIInstaller(
      fileManager: .default,
      bundle: .main,
      executableURL: macOSDir.appendingPathComponent("hatch")
    )

    try installer.install(using: BootstrapConfig(workspaceRoot: "~/Workspace", cliInstallPath: installDir.path))

    let target = installDir.appendingPathComponent("hatch")
    try expect(FileManager.default.fileExists(atPath: target.path), "missing installed hatch symlink")
    try expect(target.resolvingSymlinksInPath() == cliBinary, "installed symlink points to wrong binary")
  }
}

func testCLIInstallerReplacesStaleSymlink() throws {
  try withTempDirectory { root in
    let macOSDir = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
    let cliBinary = macOSDir.appendingPathComponent("hatch-cli")
    let installDir = root.appendingPathComponent("bin", isDirectory: true)
    let target = installDir.appendingPathComponent("hatch")
    try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
    try "#!/bin/sh\n".write(to: cliBinary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliBinary.path)
    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: URL(fileURLWithPath: "/tmp/old"))

    let installer = CLIInstaller(fileManager: .default, bundle: .main, executableURL: macOSDir.appendingPathComponent("hatch"))
    try installer.install(using: BootstrapConfig(workspaceRoot: "~/Workspace", cliInstallPath: installDir.path))

    try expect(target.resolvingSymlinksInPath() == cliBinary, "expected stale symlink to be replaced")
  }
}

func testCLIInstallerExpandsTildePath() throws {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let installDir = home.appendingPathComponent(".hatch-test-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: installDir) }

  try withTempDirectory { root in
    let macOSDir = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
    let cliBinary = macOSDir.appendingPathComponent("hatch-cli")
    try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
    try "#!/bin/sh\n".write(to: cliBinary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliBinary.path)

    let installer = CLIInstaller(fileManager: .default, bundle: .main, executableURL: macOSDir.appendingPathComponent("hatch"))
    let tildePath = "~/" + installDir.lastPathComponent
    try installer.install(using: BootstrapConfig(workspaceRoot: "~/Workspace", cliInstallPath: tildePath))

    try expect(FileManager.default.fileExists(atPath: installDir.appendingPathComponent("hatch").path), "expected tilde path expansion")
  }
}

func testCLIInstallerLocatesBundledBinaryFromAppBundle() throws {
  try withTempDirectory { root in
    let appBundle = root.appendingPathComponent("Moved Hatch.app", isDirectory: true)
    let contents = appBundle.appendingPathComponent("Contents", isDirectory: true)
    let macOSDir = contents.appendingPathComponent("MacOS", isDirectory: true)
    let resourcesDir = contents.appendingPathComponent("Resources", isDirectory: true)
    let cliBinary = macOSDir.appendingPathComponent("hatch-cli")
    let installDir = root.appendingPathComponent("bin", isDirectory: true)

    try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    try """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>dev.hatch.tests</string>
      <key>CFBundleExecutable</key>
      <string>hatch</string>
      <key>CFBundleName</key>
      <string>Hatch</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
    </dict>
    </plist>
    """.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
    try "#!/bin/sh\n".write(to: cliBinary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliBinary.path)

    guard let bundle = Bundle(url: appBundle) else {
      throw TestFailure(description: "expected app bundle to load")
    }

    let installer = CLIInstaller(fileManager: .default, bundle: bundle, executableURL: nil)
    try installer.install(using: BootstrapConfig(workspaceRoot: "~/Workspace", cliInstallPath: installDir.path))

    try expect(installDir.appendingPathComponent("hatch").resolvingSymlinksInPath() == cliBinary, "expected bundle-based binary lookup")
  }
}

func testCLIInstallerFailsWhenBinaryMissing() throws {
  try withTempDirectory { root in
    let installer = CLIInstaller(fileManager: .default, bundle: .main, executableURL: root.appendingPathComponent("missing"))
    try expectThrows(HatchError.self) {
      try installer.install(using: BootstrapConfig(workspaceRoot: "~/Workspace", cliInstallPath: root.appendingPathComponent("bin").path))
    }
  }
}
