import ProjectDescription

private let iOS: DeploymentTargets = .iOS("26.0")

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
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.sharedmodels",
            deploymentTargets: iOS,
            sources: ["Sources/SharedModels/**"]
        ),
        .target(
            name: "DesignSystem",
            destinations: [.iPad],
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
            destinations: [.iPad],
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
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.kanjilistfeature",
            deploymentTargets: iOS,
            sources: ["Sources/KanjiListFeature/**"],
            resources: ["Sources/KanjiListFeature/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "AppFeature",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.appfeature",
            deploymentTargets: iOS,
            sources: ["Sources/AppFeature/**"],
            resources: ["Sources/AppFeature/Resources/**"],
            dependencies: [
                .target(name: "KanjiListFeature"),
                .target(name: "WritingCanvas"),
                .target(name: "StudyPlan"),
                .target(name: "KanjiDetail"),
                .target(name: "Review"),
                .target(name: "Reminders"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "WritingCanvas",
            destinations: [.iPad],
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
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.writingcanvastests",
            deploymentTargets: iOS,
            sources: ["Tests/WritingCanvasTests/**"],
            dependencies: [.target(name: "WritingCanvas")]
        ),
        .target(
            name: "StudyPlan",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.studyplan",
            deploymentTargets: iOS,
            sources: ["Sources/StudyPlan/**"],
            resources: ["Sources/StudyPlan/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "StudyPlanTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.studyplantests",
            deploymentTargets: iOS,
            sources: ["Tests/StudyPlanTests/**"],
            dependencies: [.target(name: "StudyPlan")]
        ),
        .target(
            name: "KanjiDetail",
            destinations: [.iPad],
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
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.kanjidetailtests",
            deploymentTargets: iOS,
            sources: ["Tests/KanjiDetailTests/**"],
            dependencies: [.target(name: "KanjiDetail")]
        ),
        .target(
            name: "Review",
            destinations: [.iPad],
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
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.reviewtests",
            deploymentTargets: iOS,
            sources: ["Tests/ReviewTests/**"],
            dependencies: [.target(name: "Review")]
        ),
        .target(
            name: "Reminders",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.reminders",
            deploymentTargets: iOS,
            sources: ["Sources/Reminders/**"],
            resources: ["Sources/Reminders/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "RemindersTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.reminderstests",
            deploymentTargets: iOS,
            sources: ["Tests/RemindersTests/**"],
            dependencies: [.target(name: "Reminders")]
        ),
        .target(
            name: "AppFeatureTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.appfeaturetests",
            deploymentTargets: iOS,
            sources: ["Tests/AppFeatureTests/**"],
            dependencies: [.target(name: "AppFeature")]
        ),
        .target(
            name: "KanjiApp",
            destinations: [.iPad],
            product: .app,
            bundleId: "com.cobyapp.kanjiwrite",
            deploymentTargets: iOS,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": ["UIColorName": ""]
            ]),
            sources: ["Sources/KanjiApp/**"],
            resources: ["Sources/KanjiApp/Resources/**"],
            dependencies: [
                .target(name: "AppFeature"),
                .target(name: "DesignSystem"),
                .external(name: "ComposableArchitecture"),
            ],
            settings: .settings(base: ["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"])
        ),
        .target(
            name: "KanjiListFeatureTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.kanjilistfeaturetests",
            deploymentTargets: iOS,
            sources: ["Tests/KanjiListFeatureTests/**"],
            dependencies: [.target(name: "KanjiListFeature")]
        ),
        .target(
            name: "DictionaryClientTests",
            destinations: [.iPad],
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
                "StudyPlanTests",
                "KanjiDetailTests",
                "AppFeatureTests",
                "ReviewTests",
                "RemindersTests",
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
