// swift-tools-version: 5.9
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
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Metabind",
            targets: ["Metabind"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apollographql/apollo-ios", exact: "1.23.0"),
        .package(url: "https://github.com/metabindai/bindjs-apple-binary", from: "1.1.4"),
    ],
    targets: [
        .target(
            name: "Metabind",
            dependencies: [
                .product(name: "Apollo", package: "apollo-ios"),
                .product(name: "ApolloSQLite", package: "apollo-ios"),
                .product(name: "ApolloWebSocket", package: "apollo-ios"),
                .product(name: "BindJS", package: "bindjs-apple-binary"),
            ],
            path: "Sources"
        ),
    ]
)
