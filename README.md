# firebase-mac-xcframework

Pre-built macOS xcframeworks for Firebase Auth + GoogleSignIn, distributed as a Swift Package.

Google's official Firebase.zip and GoogleSignIn-iOS don't ship macOS-native xcframeworks for GoogleSignIn and its dependencies (AppAuth, GTMAppAuth). This repo builds them from source on CI and publishes them as GitHub Releases with SPM-compatible binary targets.

## SPM Usage

Add the dependency to your `Package.swift`:

```swift
.package(url: "https://github.com/SpeechifyInc/firebase-mac-xcframework.git",
         exact: "firebase-12.8.0-googlesignin-7.0.0")
```

Then depend on the products you need:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "FirebaseAuth", package: "firebase-mac-xcframework"),
        .product(name: "GoogleSignIn", package: "firebase-mac-xcframework"),
    ]
)
```

Available products:
- **`FirebaseCore`** — FirebaseCore, FirebaseCoreInternal, GoogleUtilities, FBLPromises, nanopb
- **`FirebaseAuth`** — Everything in FirebaseCore + FirebaseAuth, FirebaseCoreExtension, FirebaseInstallations, FirebaseAppCheckInterop, FirebaseAuthInterop, GTMSessionFetcher
- **`GoogleSignIn`** — GoogleSignIn, AppAuthCore, GTMAppAuth, GTMSessionFetcher

### GoogleSignIn resource bundle

The `GoogleSignIn_GoogleSignIn.bundle` (containing Google Sign-In button assets) is available as a separate download in each release. If you use `GIDSignInButton`, download and include the bundle manually. Custom sign-in UIs don't need it.

## What's included

| Framework | Source | Notes |
|-----------|--------|-------|
| FirebaseCore | Firebase.zip | Pre-built binary |
| FirebaseCoreInternal | Firebase.zip | Pre-built binary |
| FirebaseCoreExtension | Firebase.zip | Pre-built binary |
| FirebaseInstallations | Firebase.zip | Pre-built binary |
| FirebaseAuth | Firebase.zip | Pre-built binary |
| FirebaseAppCheckInterop | Firebase.zip | Pre-built binary |
| FirebaseAuthInterop | Firebase.zip | Pre-built binary |
| GoogleUtilities | Firebase.zip | Pre-built binary |
| FBLPromises | Firebase.zip | Pre-built binary |
| nanopb | Firebase.zip | Pre-built binary |
| GoogleSignIn | Built from source | macOS arm64 + x86_64 |
| AppAuthCore | Built from source | macOS arm64 + x86_64 |
| GTMAppAuth | Built from source | macOS arm64 + x86_64 |
| GTMSessionFetcher | Built from source | macOS arm64 + x86_64 |

## Building locally

```bash
FIREBASE_VERSION=12.8.0 GOOGLESIGNIN_VERSION=7.0.0 bash scripts/build.sh
```

Output: `/tmp/firebase-mac-build/zips/` (individual + combined zips)

Then generate Package.swift with real checksums:

```bash
TAG=firebase-12.8.0-googlesignin-7.0.0 bash scripts/generate-package.sh
```

## Updating versions

Trigger the GitHub Actions workflow with the desired Firebase and GoogleSignIn versions. A new release will be created automatically with updated Package.swift checksums.
