// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GoogleDiffMatchPatch",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(name: "GoogleDiffMatchPatch", targets: ["GoogleDiffMatchPatch"]),
        .library(name: "GoogleDiffMatchPatch-Dynamic", type: .dynamic, targets: ["GoogleDiffMatchPatch"]),
    ],
    targets: [
        .target(
            name: "GoogleDiffMatchPatch",
            publicHeadersPath: "Include",
            cSettings: [
                .unsafeFlags(["-fno-objc-arc"])
            ],
            linkerSettings: [
                .unsafeFlags(["-ObjC"])
            ]
        ),
    ]
)

