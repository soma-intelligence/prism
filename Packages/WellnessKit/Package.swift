// swift-tools-version: 6.2
//
//  WellnessKit
//
//  The Soma engines for health data export, food and exercise. This first
//  version holds the foundation every kit builds on:
//
//    SyncCore      one SQLite database per user, versioned records with a
//                  transactional outbox, pull cursors, a one-way upload
//                  journal, typed remote errors, retry and authentication.
//    SyncSupabase  the Supabase adapter of the neutral sync contract, and the
//                  Auth, REST and Storage clients the app's account needs.
//    HealthCloud   incremental upload of Health samples and daily rows.
//
//  SyncTesting is a build-time helper for the tests. It is not a product and
//  never ships.
//

import PackageDescription

let package = Package(
    name: "WellnessKit",
    platforms: [
        .iOS(.v26),
        .visionOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SyncCore", targets: ["SyncCore"]),
        .library(name: "SyncSupabase", targets: ["SyncSupabase"]),
        .library(name: "HealthExportCore", targets: ["HealthExportCore"]),
        .library(name: "HealthExportHealthKit", targets: ["HealthExportHealthKit"]),
        .library(name: "HealthScoring", targets: ["HealthScoring"]),
        .library(name: "HealthCloud", targets: ["HealthCloud"]),
    ],
    dependencies: [
        // The official Supabase client: Auth (Sign in with Apple, session
        // persistence and refresh), Storage, Functions and PostgREST.
        .package(url: "https://github.com/supabase/supabase-swift", .upToNextMajor(from: "2.55.3")),
    ],
    targets: [
        .target(name: "SyncCore"),
        .target(name: "SyncSupabase", dependencies: [
            "SyncCore",
            .product(name: "Supabase", package: "supabase-swift"),
        ]),
        .target(name: "HealthExportCore"),
        .target(name: "HealthExportHealthKit", dependencies: ["HealthExportCore"]),
        .target(name: "HealthScoring"),
        .target(name: "HealthCloud", dependencies: ["HealthExportCore", "SyncCore", "SyncSupabase"]),
        .target(name: "SyncTesting", dependencies: ["SyncCore"]),
        .testTarget(name: "SyncCoreTests", dependencies: ["SyncCore", "SyncTesting"]),
        .testTarget(name: "SyncSupabaseTests", dependencies: ["SyncSupabase", "SyncTesting"]),
        .testTarget(name: "RepositoryGuardTests"),
        .testTarget(name: "HealthExportCoreTests", dependencies: ["HealthExportCore"]),
        .testTarget(name: "HealthScoringTests", dependencies: ["HealthScoring"]),
        .testTarget(name: "HealthCloudTests", dependencies: ["HealthCloud", "SyncTesting"]),
    ],
    swiftLanguageModes: [.v6]
)
