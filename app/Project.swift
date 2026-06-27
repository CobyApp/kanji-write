import ProjectDescription

private let iOS: DeploymentTargets = .iOS("26.0")

let project = Project(
    name: "KanjiWrite",
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
            name: "DictionaryClient",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.dictionaryclient",
            deploymentTargets: iOS,
            sources: ["Sources/DictionaryClient/**"],
            resources: ["Sources/DictionaryClient/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
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
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
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
            dependencies: [
                .target(name: "KanjiListFeature"),
                .target(name: "WritingCanvas"),
                .target(name: "StudyPlan"),
                .target(name: "KanjiDetail"),
                .target(name: "Review"),
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
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
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
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
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
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .target(name: "WritingCanvas"),
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
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
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
            dependencies: [
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
            dependencies: [
                .target(name: "AppFeature"),
                .external(name: "ComposableArchitecture"),
            ]
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
            ])
        )
    ]
)
