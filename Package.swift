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
        .library(name: "MetabindAssistant", targets: ["MetabindAssistant"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apollographql/apollo-ios", exact: "1.23.0"),
        .package(url: "https://github.com/metabindai/bindjs-apple-binary", from: "1.1.7"),
    ],
    targets: [
        .target(
            name: "MetabindContent",
            dependencies: [
                .product(name: "Apollo", package: "apollo-ios"),
                .product(name: "ApolloSQLite", package: "apollo-ios"),
                .product(name: "ApolloWebSocket", package: "apollo-ios"),
                .product(name: "BindJS", package: "bindjs-apple-binary"),
            ],
            exclude: ["GraphQL"]
        ),
        .target(
            name: "MCPAppsHost",
            dependencies: [
                .product(name: "BindJS", package: "bindjs-apple-binary"),
            ]
        ),
        .target(
            name: "MetabindAssistant",
            dependencies: ["MCPAppsHost"]
        ),
        .testTarget(
            name: "MCPAppsHostTests",
            dependencies: ["MCPAppsHost"]
        ),
        .testTarget(
            name: "MetabindAssistantTests",
            dependencies: ["MetabindAssistant"]
        ),
    ]
)
