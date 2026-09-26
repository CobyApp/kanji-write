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
//
// Xcode 27 rejects deployment targets below iOS 15 / macOS 12, and these
// packages still declare iOS 12–13 / macOS 10.15. Each package target gets a
// supported floor. Not iOS 17+: swift-perception marks its back-ported
// `Bindable` obsoleted in iOS 17, and swift-sharing still references it.
func floor(_ settings: SettingsDictionary) -> SettingsDictionary {
    settings.merging([
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "WATCHOS_DEPLOYMENT_TARGET": "9.0",
        "TVOS_DEPLOYMENT_TARGET": "16.0",
    ]) { current, _ in current }
}

let packageSettings = PackageSettings(
    baseSettings: .settings(base: floor([:])),
    targetSettings: [
        "CasePaths": floor([:]),
        "CasePathsCore": floor([:]),
        "CasePathsMacros": floor([:]),
        "CasePathsMacrosSupport": floor([:]),
        "Clocks": floor([:]),
        "CombineSchedulers": floor([:]),
        "ConcurrencyExtras": floor([:]),
        "CustomDump": floor([:]),
        "Dependencies": floor([
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) Foundation",
        ]),
        "DependenciesMacros": floor([:]),
        "DependenciesMacrosPlugin": floor([:]),
        "GRDB": floor([:]),
        "GRDBSQLite": floor([:]),
        "IdentifiedCollections": floor([:]),
        "InternalCollectionsUtilities": floor([:]),
        "IssueReporting": floor([:]),
        "OrderedCollections": floor([:]),
        "Perception": floor([:]),
        "PerceptionCore": floor([:]),
        "PerceptionMacros": floor([:]),
        "Sharing": floor([:]),
        "Sharing1": floor([:]),
        "Sharing2": floor([:]),
        "SwiftBasicFormat": floor([:]),
        "SwiftCompilerPlugin": floor([:]),
        "SwiftCompilerPluginMessageHandling": floor([:]),
        "SwiftDiagnostics": floor([:]),
        "SwiftIfConfig": floor([:]),
        "SwiftNavigation": floor([:]),
        "SwiftOperators": floor([:]),
        "SwiftParser": floor([:]),
        "SwiftParserDiagnostics": floor([:]),
        "SwiftSyntax": floor([:]),
        "SwiftSyntax509": floor([:]),
        "SwiftSyntax510": floor([:]),
        "SwiftSyntax600": floor([:]),
        "SwiftSyntax601": floor([:]),
        "SwiftSyntax602": floor([:]),
        "SwiftSyntax603": floor([:]),
        "SwiftSyntaxBuilder": floor([:]),
        "SwiftSyntaxMacroExpansion": floor([:]),
        "SwiftSyntaxMacros": floor([:]),
        "SwiftUINavigation": floor([:]),
        "UIKitNavigation": floor([:]),
        "UIKitNavigationShim": floor([:]),
        "XCTestDynamicOverlay": floor([:]),
        "_SwiftSyntaxCShims": floor([:]),
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
