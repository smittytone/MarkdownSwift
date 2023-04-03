// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Markdowner",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v12),
    ],
    products: [
        .library(
            name: "Markdowner",
            targets: ["Markdowner"])
    ],
    dependencies: [
        // None
    ],
    targets: [
        .target(
            name: "Markdowner",
            dependencies: [],
            path: "Sources",
            resources: [
                .copy("Assets/markdown-it.min.js"),
                .copy("Assets/styles/default.css")
            ])
    ]
)
