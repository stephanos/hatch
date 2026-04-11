import Foundation

package struct CLIInstaller {
  private let fileManager: FileManager
  private let bundle: Bundle
  private let executableURL: URL?

  package init(
    fileManager: FileManager = .default,
    bundle: Bundle = .main,
    executableURL: URL? = Bundle.main.executableURL
  ) {
    self.fileManager = fileManager
    self.bundle = bundle
    self.executableURL = executableURL
  }

  package func install(using bootstrap: BootstrapConfig) throws {
    let sourceBinary = try locateCLIBinary()
    let installDirectory = resolvePath(bootstrap.cliInstallPath)

    try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

    let target = installDirectory.appendingPathComponent("hatch")
    let hasExistingTarget: Bool
    if fileManager.fileExists(atPath: target.path) {
      hasExistingTarget = true
    } else if (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
      hasExistingTarget = true
    } else {
      hasExistingTarget = false
    }

    if hasExistingTarget {
      try fileManager.removeItem(at: target)
    }

    try fileManager.createSymbolicLink(at: target, withDestinationURL: sourceBinary)
  }

  private func locateCLIBinary() throws -> URL {
    let candidates = [
      bundle.bundleURL.appendingPathComponent("Contents/MacOS/hatch-cli"),
      executableURL?.deletingLastPathComponent().appendingPathComponent("hatch-cli"),
    ].compactMap { $0 }

    for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
      return candidate
    }

    throw HatchError.message("Could not locate bundled hatch-cli to install")
  }

  private func resolvePath(_ value: String) -> URL {
    URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
  }
}
