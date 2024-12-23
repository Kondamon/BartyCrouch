// swift-tools-version:5.6
import PackageDescription

let package = Package(
  name: "BartyCrouch",
  platforms: [.macOS(.v10_15), .iOS(.v15)],
  products: [
    .executable(name: "bartycrouch", targets: ["BartyCrouch"]),
    .library(name: "BartyCrouchConfiguration", targets: ["BartyCrouchConfiguration"]),
    .library(name: "BartyCrouchKit", targets: ["BartyCrouchKit"]),
    .library(name: "BartyCrouchTranslator", targets: ["BartyCrouchTranslator"]),
  ],
  dependencies: [
    .package(url: "https://github.com/Flinesoft/HandySwift.git", from: "3.2.0"),
    .package(url: "https://github.com/Flinesoft/Microya.git", branch: "support/without-combine"),
    .package(url: "https://github.com/Flinesoft/MungoHealer.git", from: "0.3.4"),
    .package(url: "https://github.com/onevcat/Rainbow.git", from: "3.1.5"),
    .package(url: "https://github.com/jakeheis/SwiftCLI.git", from: "6.0.3"),
    .package(url: "https://github.com/jdfergason/swift-toml.git", branch: "master"),
    .package(url: "https://github.com/apple/swift-syntax.git", from: "508.0.0"),

    // A collection of tools for debugging, diffing, and testing your application's data structures.
    .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "0.3.0"),
  ],
  targets: [
    .executableTarget(
      name: "BartyCrouch",
      dependencies: ["BartyCrouchKit"]
    ),
    .target(
      name: "BartyCrouchKit",
      dependencies: [
        "BartyCrouchConfiguration",
        "BartyCrouchTranslator",
        "HandySwift",
        "MungoHealer",
        "Rainbow",
        "SwiftCLI",
        .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        "BartyCrouchUtility",
      ]
    ),
    .testTarget(
      name: "BartyCrouchKitTests",
      dependencies: ["BartyCrouchKit"]
    ),
    .target(
      name: "BartyCrouchConfiguration",
      dependencies: [
        "MungoHealer",
        .product(name: "Toml", package: "swift-toml"),
        "BartyCrouchUtility",
      ]
    ),
    .testTarget(
      name: "BartyCrouchConfigurationTests",
      dependencies: [
        "BartyCrouchConfiguration",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Toml", package: "swift-toml"),
      ]
    ),
    .target(
      name: "BartyCrouchTranslator",
      dependencies: ["HandySwift", "Microya", "MungoHealer"]
    ),
    .testTarget(
      name: "BartyCrouchTranslatorTests",
      dependencies: ["BartyCrouchTranslator"],
      exclude: ["Secrets/secrets.json.sample"],
      resources: [
        .copy("Secrets/secrets.json")
      ]
    ),
    .target(name: "BartyCrouchUtility"),
  ]
)
