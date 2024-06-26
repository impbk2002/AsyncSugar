// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tetra",
    platforms: [
        .iOS(.v13),
        .macCatalyst(.v13),
        .tvOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Tetra",
            targets: ["Tetra"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.1.0")),
        .package(
          url: "https://github.com/apple/swift-atomics.git",
          .upToNextMajor(from: "1.2.0") // or `.upToNextMinor
        ),

    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "CriticalSection",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ],
            swiftSettings: [
                .swiftLanguageVersion(.v6),
                .enableExperimentalFeature("StaticExclusiveOnly"),
                .enableExperimentalFeature("RawLayout"),
                .enableExperimentalFeature("BuiltinModule")
            ]
        ),
        .target(
            name: "BackportDiscardingTaskGroup",
            swiftSettings: [
                .enableUpcomingFeature("FullTypedThrows"),
                .enableExperimentalFeature("IsolatedAny"),
                .swiftLanguageVersion(.v6)
            ]
        ),
        .target(
            name: "Tetra",
            dependencies: [
                .product(name: "DequeModule", package: "swift-collections"),
                "BackPortAsyncSequence",
                "CriticalSection",
                "BackportDiscardingTaskGroup",
            ],
            swiftSettings: [
                .enableUpcomingFeature("FullTypedThrows"),
                .enableExperimentalFeature("IsolatedAny"),
                .swiftLanguageVersion(.v6)
            ]
        ),
        .target(
            name: "BackPortAsyncSequence",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageVersion(.v6),
            ]
        ),
        .testTarget(
            name: "TetraTests",
            dependencies: [
                "Tetra"
            ],
            resources: [.process("Resources")]
        )
    ]
)
