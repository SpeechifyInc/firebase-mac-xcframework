# firebase-mac-xcframework

Pre-built macOS xcframeworks for Firebase Auth + GoogleSignIn.

Google's official Firebase.zip and GoogleSignIn-iOS don't ship macOS-native xcframeworks for GoogleSignIn and its dependencies (AppAuth, GTMAppAuth). This repo builds them from source on CI and publishes them as GitHub Releases.

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
| GTMSessionFetcherCore | Built from source | macOS arm64 + x86_64 |

## Usage

Download the latest release zip and extract the xcframeworks into your `vendor/` directory. Reference them as binary targets in your SPM package.

## Building locally

```bash
FIREBASE_VERSION=12.8.0 GOOGLESIGNIN_VERSION=7.0.0 bash scripts/build.sh
```

Output: `/tmp/firebase-mac-build/firebase-mac-xcframeworks.zip`

## Updating versions

Trigger the GitHub Actions workflow with the desired Firebase and GoogleSignIn versions. A new release will be created automatically.
