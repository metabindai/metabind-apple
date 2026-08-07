// swift-tools-version: 5.11
//
// Package.swift
//
// © 2025 Yap Studios LLC
//

import PackageDescription

let package = Package(
    name: "metabind-apple",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "MetabindContent", targets: ["MetabindContent"]),
        .library(name: "MCPAppsHost", targets: ["MCPAppsHost"]),
        .library(name: "MetabindAI", targets: ["MetabindAI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apollographql/apollo-ios", exact: "1.25.7"),
        .package(url: "https://github.com/metabindai/bindjs-apple.git", from: "1.1.6"),
    ],
    targets: [
        .target(
            name: "MetabindContent",
            dependencies: [
                .product(name: "Apollo", package: "apollo-ios"),
                .product(name: "ApolloSQLite", package: "apollo-ios"),
                .product(name: "ApolloWebSocket", package: "apollo-ios"),
                .product(name: "BindJS", package: "bindjs-apple"),
            ],
            exclude: ["GraphQL"]
        ),
        .target(
            name: "MCPAppsHost",
            dependencies: [
                .product(name: "BindJS", package: "bindjs-apple"),
            ]
        ),
        .target(
            name: "MetabindAI",
            dependencies: ["MCPAppsHost"]
        ),
        .testTarget(
            name: "MCPAppsHostTests",
            dependencies: ["MCPAppsHost"]
        ),
        .testTarget(
            name: "MetabindAITests",
            dependencies: ["MetabindAI"]
        ),
    ]
)
