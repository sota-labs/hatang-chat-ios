// swift-tools-version: 6.0
import PackageDescription

// Hatang support chat for iOS. No dependencies. macOS is listed only so the pure core and its tests
// run with `swift test` on a Mac or CI; the UI target compiles to nothing outside iOS.
let package = Package(
    name: "HatangChat",
    defaultLocalization: "vi",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HatangChat", targets: ["HatangChat"]),
        .library(name: "HatangChatCore", targets: ["HatangChatCore"]),
    ],
    targets: [
        .target(name: "HatangChatCore"),
        .target(name: "HatangChat", dependencies: ["HatangChatCore"]),
        .testTarget(name: "HatangChatCoreTests", dependencies: ["HatangChatCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ConformanceTests", dependencies: ["HatangChatCore"]),
        .testTarget(name: "HatangChatTests", dependencies: ["HatangChat"]),
    ],
    swiftLanguageModes: [.v6]
)
