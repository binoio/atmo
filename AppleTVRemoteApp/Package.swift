// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Atmo",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Atmo",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Atmo",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("IsolatedDeinit")
            ],
            linkerSettings: [
                // Sparkle.framework is embedded in Contents/Frameworks by Scripts/bundle.sh
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "AtmoTests",
            dependencies: ["Atmo"],
            path: "Tests"
        )
    ]
)
