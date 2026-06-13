// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Worktime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Worktime", targets: ["Worktime"])
    ],
    targets: [
        .executableTarget(
            name: "Worktime",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "WorktimeTests",
            dependencies: ["Worktime"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
