// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Detect local Frameworks/ directory for development builds.
// If present, use local paths; otherwise pull from GitHub release.
let frameworksDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Frameworks")
let useLocalFrameworks = FileManager.default.fileExists(
    atPath: frameworksDir.appendingPathComponent("FirebaseCore.xcframework").path
)

let releaseURL = "https://github.com/SpeechifyInc/firebase-mac-xcframework/releases/download/firebase-12.8.0-googlesignin-7.0.0-r3"

func binaryTarget(name: String, checksum: String) -> Target {
    if useLocalFrameworks {
        return .binaryTarget(name: name, path: "Frameworks/\(name).xcframework")
    } else {
        return .binaryTarget(
            name: name,
            url: "\(releaseURL)/\(name).xcframework.zip",
            checksum: checksum
        )
    }
}

let package = Package(
    name: "firebase-mac-xcframework",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "FirebaseAuth", targets: ["FirebaseAuthTarget"]),
        .library(name: "FirebaseCore", targets: ["FirebaseCoreTarget"]),
        .library(name: "GoogleSignIn", targets: ["GoogleSignInTarget"]),
    ],
    targets: [
        // -- Wrapper targets (SPM requires at least one source file per target) --
        .target(
            name: "FirebaseAuthTarget",
            dependencies: [
                "FirebaseCoreTarget",
                "FirebaseAuth",
                "FirebaseCoreExtension",
                "FirebaseInstallations",
                "FirebaseAppCheckInterop",
                "FirebaseAuthInterop",
                "GTMSessionFetcher",
            ],
            path: "Sources/FirebaseAuth"
        ),
        .target(
            name: "FirebaseCoreTarget",
            dependencies: [
                "FirebaseCore",
                "FirebaseCoreInternal",
                "GoogleUtilities",
                "FBLPromises",
                "nanopb",
            ],
            path: "Sources/FirebaseCore"
        ),
        .target(
            name: "GoogleSignInTarget",
            dependencies: [
                "GoogleSignIn",
                "AppAuth",
                "AppAuthCore",
                "GTMAppAuth",
                "GTMSessionFetcher",
            ],
            path: "Sources/GoogleSignIn"
        ),

        // -- Binary targets --
        binaryTarget(name: "AppAuth", checksum: "4703460badb6bd1b8a599be2f791f50273f5b0080fe8332982be04e33946cd1a"),
        binaryTarget(name: "AppAuthCore", checksum: "3b57174ad2f383455f3a8c6b4172811c782f4f92620cbfb26843deee80d5de52"),
        binaryTarget(name: "FBLPromises", checksum: "72be239461487effb2dc9240f7c803cd92da6b2cbd994823e5e7bc6cce65102d"),
        binaryTarget(name: "FirebaseAppCheckInterop", checksum: "8c8f3bd9a0465f1d7ff07564e29f5580429f2ef7ac17210807e8bf4edb12430e"),
        binaryTarget(name: "FirebaseAuth", checksum: "df6c60438c7776b18f7fc0aa78b0172bd00bf973cb12f2fd93521959c86322f3"),
        binaryTarget(name: "FirebaseAuthInterop", checksum: "dc8f5af444e9eed71ed28bafaf05a44c94b75c5dbf8daf585bd60031bf7cfe04"),
        binaryTarget(name: "FirebaseCore", checksum: "7e969d3d2ff736278c64afb4b198b84f3ba02f260fced5870a391c1654b185f1"),
        binaryTarget(name: "FirebaseCoreExtension", checksum: "d4d4bbefcdefabd9828515cc262375e19a86aa646f8c9201e80360829cf85eec"),
        binaryTarget(name: "FirebaseCoreInternal", checksum: "95dd650863d5e31150c9b3c509b8c44cb0540f178ac65c87b5145a40445048d3"),
        binaryTarget(name: "FirebaseInstallations", checksum: "f2c7b2cbd66d5c4adb99a1f8e9389f9826ce2957e76f41ff8d71a7e22a77aa82"),
        binaryTarget(name: "GoogleSignIn", checksum: "ed8fc4a6faff0627b3d37f07a55baded81487b0a2aef350e09e1c11768d293d3"),
        binaryTarget(name: "GoogleUtilities", checksum: "9ead8fbe062244abfa76d3c886c1d5788e032ca9057f07727d61b5dbaa0833e4"),
        binaryTarget(name: "GTMAppAuth", checksum: "0b0177ebc24eeced8ab6a184ef2179294291cdfee8c77c61f54c3e992578ca89"),
        binaryTarget(name: "GTMSessionFetcher", checksum: "6b16c1026ea8b077ddeea758205d74971db246e1bbb2e13cf434f8dd072aa00d"),
        binaryTarget(name: "nanopb", checksum: "b6d5a4adf894fd58405e17ed0f95a6e9d38c48202b57638b8ec1558b3dc7097c"),
    ]
)
