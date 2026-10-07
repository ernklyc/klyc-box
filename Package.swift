// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "klycbox",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KLYCKit", targets: ["KLYCKit"]),
        .executable(name: "klycbox", targets: ["klycbox"]),
        .executable(name: "KLYCBoxApp", targets: ["KLYCBoxApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "KLYCKit", path: "Sources/KLYCKit", swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
        .executableTarget(
            name: "klycbox",
            dependencies: ["KLYCKit", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/klycbox"),
        .executableTarget(
            name: "KLYCBoxApp",
            dependencies: ["KLYCKit", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/KLYCBoxApp",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "KLYCKitTests", dependencies: ["KLYCKit"], path: "Tests/KLYCKitTests"),
    ]
)
