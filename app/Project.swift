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
        // Sign every target — app, widget, and watch — with the same developer
        // account and automatically-managed profiles. Without a project-wide
        // team the embedded widget/watch binaries get a different signature than
        // the parent app ("Embedded binary is not signed with the same
        // certificate…") and the install fails.
        "DEVELOPMENT_TEAM": "3Y8YH8GWMM",
        "CODE_SIGN_STYLE": "Automatic",
        // App version, shared by every target so the app, widget and watch
        // extension always ship the same numbers (a mismatch fails App Store
        // validation). Bump MARKETING_VERSION for a user-facing release and
        // CURRENT_PROJECT_VERSION for every upload of that version.
        "MARKETING_VERSION": "1.1.0",
        "CURRENT_PROJECT_VERSION": "2",
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
            dependencies: [.target(name: "TestMode"), .target(name: "Review")]
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
                // Home-screen name: マイカンジ (mykanji).
                "CFBundleDisplayName": "マイカンジ",
                "UILaunchScreen": ["UIColorName": ""],
                // mykanji://review | study | notebook — opened by the daily
                // reminder and the home-screen widget.
                "CFBundleURLTypes": [
                    ["CFBundleURLName": "com.cobyapp.kanjiwrite", "CFBundleURLSchemes": ["mykanji"]],
                ],
                // Portrait-only on iPhone — the whole UI is one portrait column.
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                // iPad has to offer all four. An iPad app that participates in
                // multitasking is resizable by definition, so App Store
                // validation rejects a narrower list (error 90474), and
                // UIRequiresFullScreen is no longer an escape hatch — it is
                // deprecated as of iPadOS 26, which is this app's floor.
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
            ]),
            sources: ["Sources/KanjiApp/**"],
            resources: ["Sources/KanjiApp/Resources/**"],
            dependencies: [
                .target(name: "AppFeature"),
                .target(name: "DesignSystem"),
                .target(name: "KanjiWidget"),
                // Embed the Apple Watch app on iOS/iPadOS only — Mac Catalyst
                // can't contain a watchOS app.
                .target(name: "KanjiWatch", condition: .when([.ios])),
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
                // Shown in the widget gallery, and required by App Store
                // validation for an embedded extension.
                "CFBundleDisplayName": "マイカンジ",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["Sources/KanjiWidget/**"],
            resources: ["Sources/KanjiWidget/Resources/**"],
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
                "CFBundleDisplayName": "マイカンジ",
                "WKApplication": true,
                "WKCompanionAppBundleIdentifier": "com.cobyapp.kanjiwrite",
            ]),
            sources: ["Sources/KanjiWatch/**"],
            resources: ["Sources/KanjiWatch/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
            ],
            // No signing settings here on purpose: the watch app inherits the
            // project-wide DEVELOPMENT_TEAM so it matches the parent app's
            // certificate, which a device install requires.
            settings: .settings(base: [
                // A watch app has to carry its own icon: App Store validation
                // rejects the whole upload for a missing CFBundleIconName here,
                // even though the phone app's icon is right there in the bundle.
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            ])
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
