import ProjectDescription

private let iOS: DeploymentTargets = .iOS("26.0")

// iPhone + iPad + Mac (via Mac Catalyst). The whole UI is UIKit/SwiftUI +
// PencilKit, which all run under Catalyst, so the same build serves the Mac.
private let appDestinations: Destinations = [.iPhone, .iPad, .macCatalyst]

let project = Project(
    name: "KanjiWrite",
    options: .options(
        // Japanese is the development/base language for the String Catalogs
        // (sourceLanguage = "ja"); declaring it here makes each generated
        // resource bundle's CFBundleDevelopmentRegion "ja" and registers the
        // translated regions so Locale-based lookup resolves ko/zh-Hans/en.
        defaultKnownRegions: ["ja", "ko", "zh-Hans", "en"],
        developmentRegion: "ja"
    ),
    settings: .settings(base: [
        // The device runs a newer iOS (27 beta) than the build toolchain
        // (Xcode 26.5). Xcode's "debug dylib" launch path (a separate
        // *.debug.dylib loaded at startup) is fragile across that gap and
        // aborts during libxpc initialization before app code runs. Disabling
        // it falls back to a single-binary debug build that launches normally.
        "ENABLE_DEBUG_DYLIB": "NO",
    ]),
    targets: [
        .target(
            name: "SharedModels",
            // Also builds for watchOS so the Watch app can share the snapshot model.
            destinations: [.iPhone, .iPad, .macCatalyst, .appleWatch],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.sharedmodels",
            deploymentTargets: .multiplatform(iOS: "26.0", watchOS: "11.0"),
            sources: ["Sources/SharedModels/**"]
        ),
        .target(
            name: "DesignSystem",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.designsystem",
            deploymentTargets: iOS,
            sources: ["Sources/DesignSystem/**"],
            resources: ["Sources/DesignSystem/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
            ]
        ),
        .target(
            name: "DictionaryClient",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.dictionaryclient",
            deploymentTargets: iOS,
            sources: ["Sources/DictionaryClient/**"],
            resources: ["Sources/DictionaryClient/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
                .external(name: "GRDB"),
            ]
        ),
        .target(
            name: "KanjiListFeature",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.kanjilistfeature",
            deploymentTargets: iOS,
            sources: ["Sources/KanjiListFeature/**"],
            resources: ["Sources/KanjiListFeature/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
            ]
        ),
        .target(
            name: "AppFeature",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.appfeature",
            deploymentTargets: iOS,
            sources: ["Sources/AppFeature/**"],
            resources: ["Sources/AppFeature/Resources/**"],
            dependencies: [
                .target(name: "KanjiListFeature"),
                .target(name: "WritingCanvas"),
                .target(name: "KanjiDetail"),
                .target(name: "Review"),
                .target(name: "Reminders"),
                .target(name: "Worksheet"),
                .target(name: "Practice"),
                .target(name: "TestMode"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "WritingCanvas",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.writingcanvas",
            deploymentTargets: iOS,
            sources: ["Sources/WritingCanvas/**"],
            resources: ["Sources/WritingCanvas/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "WritingCanvasTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.writingcanvastests",
            deploymentTargets: iOS,
            sources: ["Tests/WritingCanvasTests/**"],
            dependencies: [.target(name: "WritingCanvas")]
        ),
        .target(
            name: "KanjiDetail",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.kanjidetail",
            deploymentTargets: iOS,
            sources: ["Sources/KanjiDetail/**"],
            resources: ["Sources/KanjiDetail/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "WritingCanvas"),
                .target(name: "Review"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "KanjiDetailTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.kanjidetailtests",
            deploymentTargets: iOS,
            sources: ["Tests/KanjiDetailTests/**"],
            dependencies: [.target(name: "KanjiDetail")]
        ),
        .target(
            name: "Practice",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.practice",
            deploymentTargets: iOS,
            sources: ["Sources/Practice/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "WritingCanvas"),
                .target(name: "Review"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "PracticeTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.practicetests",
            deploymentTargets: iOS,
            sources: ["Tests/PracticeTests/**"],
            dependencies: [.target(name: "Practice")]
        ),
        .target(
            name: "Review",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.review",
            deploymentTargets: iOS,
            sources: ["Sources/Review/**"],
            resources: ["Sources/Review/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "ReviewTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.reviewtests",
            deploymentTargets: iOS,
            sources: ["Tests/ReviewTests/**"],
            dependencies: [.target(name: "Review")]
        ),
        .target(
            name: "Reminders",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.reminders",
            deploymentTargets: iOS,
            sources: ["Sources/Reminders/**"],
            resources: ["Sources/Reminders/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DesignSystem"),
                .target(name: "Review"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "RemindersTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.reminderstests",
            deploymentTargets: iOS,
            sources: ["Tests/RemindersTests/**"],
            dependencies: [.target(name: "Reminders")]
        ),
        .target(
            name: "TestMode",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.testmode",
            deploymentTargets: iOS,
            sources: ["Sources/TestMode/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "WritingCanvas"),
                .target(name: "Review"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "TestModeTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.testmodetests",
            deploymentTargets: iOS,
            sources: ["Tests/TestModeTests/**"],
            dependencies: [.target(name: "TestMode")]
        ),
        .target(
            name: "Worksheet",
            destinations: appDestinations,
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.worksheet",
            deploymentTargets: iOS,
            sources: ["Sources/Worksheet/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "WritingCanvas"),
                .target(name: "Review"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "WorksheetTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.worksheettests",
            deploymentTargets: iOS,
            sources: ["Tests/WorksheetTests/**"],
            dependencies: [.target(name: "Worksheet")]
        ),
        .target(
            name: "AppFeatureTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.appfeaturetests",
            deploymentTargets: iOS,
            sources: ["Tests/AppFeatureTests/**"],
            dependencies: [.target(name: "AppFeature")]
        ),
        .target(
            name: "KanjiApp",
            destinations: appDestinations,
            product: .app,
            bundleId: "com.cobyapp.kanjiwrite",
            deploymentTargets: iOS,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": ["UIColorName": ""],
                // Portrait-only on both iPhone and iPad — the whole UI is designed
                // as a single portrait column.
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait"],
            ]),
            sources: ["Sources/KanjiApp/**"],
            resources: ["Sources/KanjiApp/Resources/**"],
            dependencies: [
                .target(name: "AppFeature"),
                .target(name: "DesignSystem"),
                .target(name: "KanjiWidget"),
                // NOTE: the KanjiWatch app is embedded on machines that have the
                // watchOS platform installed. Add `.target(name: "KanjiWatch")`
                // here to bundle it into the iPhone app. (Left out by default so
                // the iOS/Catalyst build doesn't require the watchOS SDK.)
                .external(name: "ComposableArchitecture"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                // App Group only on iOS/iPadOS (widget data sharing). Mac Catalyst
                // signs "to run locally", which can't carry the App Group
                // entitlement, so skip it there.
                "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "Sources/KanjiApp/KanjiApp.entitlements",
                "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "Sources/KanjiApp/KanjiApp.entitlements",
            ])
        ),
        .target(
            name: "KanjiWidget",
            destinations: appDestinations,
            product: .appExtension,
            bundleId: "com.cobyapp.kanjiwrite.widget",
            deploymentTargets: iOS,
            infoPlist: .extendingDefault(with: [
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["Sources/KanjiWidget/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DesignSystem"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "Sources/KanjiWidget/KanjiWidget.entitlements",
                "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "Sources/KanjiWidget/KanjiWidget.entitlements",
            ])
        ),
        .target(
            name: "KanjiWatch",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "com.cobyapp.kanjiwrite.watchkitapp",
            deploymentTargets: .watchOS("11.0"),
            infoPlist: .extendingDefault(with: [
                "WKApplication": true,
                "WKCompanionAppBundleIdentifier": "com.cobyapp.kanjiwrite",
            ]),
            sources: ["Sources/KanjiWatch/**"],
            dependencies: [
                .target(name: "SharedModels"),
            ]
        ),
        .target(
            name: "KanjiListFeatureTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.kanjilistfeaturetests",
            deploymentTargets: iOS,
            sources: ["Tests/KanjiListFeatureTests/**"],
            dependencies: [.target(name: "KanjiListFeature")]
        ),
        .target(
            name: "DictionaryClientTests",
            destinations: appDestinations,
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.dictionaryclienttests",
            deploymentTargets: iOS,
            sources: ["Tests/DictionaryClientTests/**"],
            dependencies: [.target(name: "DictionaryClient")]
        ),
    ],
    schemes: [
        .scheme(
            name: "KanjiWrite",
            shared: true,
            buildAction: .buildAction(targets: ["KanjiApp"]),
            testAction: .targets([
                "KanjiListFeatureTests",
                "DictionaryClientTests",
                "WritingCanvasTests",
                "KanjiDetailTests",
                "AppFeatureTests",
                "ReviewTests",
                "RemindersTests",
                "PracticeTests",
                "TestModeTests",
                "WorksheetTests",
            ]),
            // The iOS 27 beta device + Xcode 26.5 toolchain mismatch makes the
            // injected debug dylibs (Main Thread Checker / Thread Performance
            // Checker) SIGKILL the process during dyld's inserted-library load.
            // Disable them so a debug Run launches on the device.
            runAction: .runAction(
                configuration: .debug,
                executable: "KanjiApp",
                diagnosticsOptions: .options(
                    mainThreadCheckerEnabled: false,
                    performanceAntipatternCheckerEnabled: false
                )
            )
        )
    ]
)
