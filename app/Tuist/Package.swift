// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

// swift-dependencies declares `Foundation` (and Clocks / CombineSchedulers /
// FoundationNetworking) as *default* package traits. Its Foundation-backed
// built-in dependency values — `\.date`, `\.calendar`, `\.uuid`, `\.timeZone`,
// `\.locale` — live behind `#if Foundation`. Tuist's SPM integration does not
// enable SPM traits, so that flag is missing and those keys vanish (a clean
// build then fails at `@Dependency(\.date)`). Re-enable the `Foundation`
// compilation condition on the `Dependencies` target. We enable only
// `Foundation`: the others would pull `@_exported import Clocks /
// CombineSchedulers` for modules we neither link nor use.
let packageSettings = PackageSettings(
    targetSettings: [
        "Dependencies": [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) Foundation",
        ],
    ]
)
#endif

let package = Package(
    name: "KanjiWrite",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.1"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.0"),
    ]
)
