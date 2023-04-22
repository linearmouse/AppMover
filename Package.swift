// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppMover",
    products: [
        .library(
            name: "AppMover",
            targets: ["AppMover"]),
    ],
    targets: [
        .target(
            name: "AppMover"),
    ]
)
