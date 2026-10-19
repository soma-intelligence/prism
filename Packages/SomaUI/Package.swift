// swift-tools-version: 6.2
//
//  SomaUI
//
//  The Soma design system: the tokens every surface reads from, and the
//  components built on top of them.
//
//    SomaUI                the shipping module: theme, tokens, components.
//    SomaUIPreviewSupport  sample fixtures for `#Preview` and the component
//                          gallery. Never linked into a release surface.
//

import PackageDescription

let package = Package(
    name: "SomaUI",
    platforms: [
        .iOS(.v26),
        .visionOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SomaUI", targets: ["SomaUI"]),
        .library(name: "SomaUIPreviewSupport", targets: ["SomaUIPreviewSupport"]),
    ],
    targets: [
        .target(
            name: "SomaUI",
            // The vendored muscle art's licence travels with its source, not in the bundle.
            exclude: ["Components/Readings/MuscleArt/LICENSE-MuscleMap.txt"]
        ),
        .target(name: "SomaUIPreviewSupport", dependencies: ["SomaUI"]),
        .testTarget(name: "SomaUITests", dependencies: ["SomaUI"]),
    ],
    swiftLanguageModes: [.v6]
)
