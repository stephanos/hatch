import Foundation

let tests =
  cliTests
  + configTests
  + installerTests
  + appModelTests
  + workspaceIntegrationTests
  + hookIntegrationTests
  + cliIntegrationTests
var failures: [String] = []

for test in tests {
  do {
    try test.run()
    print("PASS \(test.name)")
  } catch {
    failures.append("\(test.name): \(error)")
    fputs("FAIL \(test.name): \(error)\n", stderr)
  }
}

if !failures.isEmpty {
  Foundation.exit(1)
}
