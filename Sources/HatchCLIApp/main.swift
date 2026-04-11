import Foundation
import HatchCLIKit
import HatchCore

@main
struct HatchCLIExecutable {
  static func main() {
    do {
      try HatchCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch let error as HatchError {
      fputs("hatch: \(error.localizedDescription)\n", stderr)
      Foundation.exit(1)
    } catch let error as CLIError {
      fputs("hatch: \(error.message)\n", stderr)
      Foundation.exit(1)
    } catch {
      fputs("hatch: \(error.localizedDescription)\n", stderr)
      Foundation.exit(1)
    }
  }
}
