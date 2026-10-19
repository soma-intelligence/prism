// swift-tools-version: 6.2
//
//  SomaWidgetKit
//
//  Shared model for the Soma widgets.
//
//    SomaWidgetKit   snapshot, store, links, log inbox. No UI.
//    SomaWidgetUI    the widget views, built on SomaUI.
//

import PackageDescription

let package = Package(
    name: "SomaWidgetKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SomaWidgetKit", targets: ["SomaWidgetKit"]),
        .library(name: "SomaWidgetUI", targets: ["SomaWidgetUI"]),
    ],
    dependencies: [
        .package(path: "../../Packages/SomaUI"),
    ],
    targets: [
        .target(name: "SomaWidgetKit"),
        .target(
            name: "SomaWidgetUI",
            dependencies: [
                "SomaWidgetKit",
                .product(name: "SomaUI", package: "SomaUI"),
            ]
        ),
        .testTarget(name: "SomaWidgetKitTests", dependencies: ["SomaWidgetKit"]),
        .testTarget(name: "SomaWidgetUITests", dependencies: ["SomaWidgetUI"]),
    ],
    swiftLanguageModes: [.v6]
)
