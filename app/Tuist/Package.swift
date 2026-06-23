// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KanjiWrite",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.1"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.0"),
    ]
)
