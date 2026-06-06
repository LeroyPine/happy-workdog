// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "happy-workdog",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "happy-workdog", targets: ["happy-workdog"])
    ],
    targets: [
        .executableTarget(
            name: "happy-workdog",
            resources: [
                .process("donate-coffee.png"),
                .process("author-avatar.png"),
            ]
        ),
        .testTarget(
            name: "happy-workdogTests",
            dependencies: ["happy-workdog"],
            swiftSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
