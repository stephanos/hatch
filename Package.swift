// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "hatch",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "hatch", targets: ["hatch"]),
    .executable(name: "hatch-cli", targets: ["hatch-cli"]),
    .executable(name: "hatch-tests", targets: ["hatch-tests"]),
  ],
  dependencies: [
    .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.4.4")
  ],
  targets: [
    .target(
      name: "HatchSupport",
      path: "Sources/HatchSupport"
    ),
    .target(
      name: "HatchCore",
      dependencies: [
        "HatchSupport",
        .product(name: "TOMLDecoder", package: "TOMLDecoder"),
      ],
      path: "Sources/HatchCore"
    ),
    .target(
      name: "HatchAppState",
      dependencies: ["HatchCore"],
      path: "Sources/HatchApp/State"
    ),
    .executableTarget(
      name: "hatch",
      dependencies: ["HatchCore", "HatchAppState", "HatchSupport"],
      path: "Sources/HatchApp",
      exclude: ["State"],
      resources: [
        .process("Resources")
      ]
    ),
    .target(
      name: "HatchCLIKit",
      dependencies: ["HatchCore"],
      path: "Sources/HatchCLIKit"
    ),
    .executableTarget(
      name: "hatch-cli",
      dependencies: ["HatchCLIKit"],
      path: "Sources/HatchCLIApp"
    ),
    .executableTarget(
      name: "hatch-tests",
      dependencies: ["HatchCLIKit", "HatchCore", "HatchAppState", "HatchSupport"],
      path: "Tests/HatchTests"
    ),
  ],
  swiftLanguageModes: [.v6]
)
