#!/bin/bash
set -euo pipefail

# =============================================================================
# Build Firebase + GoogleSignIn macOS xcframeworks
#
# Produces a single zip containing:
#
#   From Firebase.zip (pre-built by Google):
#     FirebaseCore, FirebaseCoreInternal, FirebaseCoreExtension,
#     FirebaseInstallations, FirebaseAuth, FirebaseAppCheckInterop,
#     FirebaseAuthInterop, GoogleUtilities, FBLPromises, nanopb
#
#   Built from source for macOS (arm64 + x86_64):
#     GoogleSignIn.xcframework — merged static lib containing GoogleSignIn,
#     AppAuth, GTMAppAuth, and GTMSessionFetcherCore. Only GoogleSignIn's
#     public headers are exposed (others are link-time-only deps).
#
# Usage:
#   FIREBASE_VERSION=12.8.0 GOOGLESIGNIN_VERSION=7.0.0 bash scripts/build.sh
# =============================================================================

FIREBASE_VERSION="${FIREBASE_VERSION:-12.8.0}"
GOOGLESIGNIN_VERSION="${GOOGLESIGNIN_VERSION:-7.0.0}"
WORK_DIR="/tmp/firebase-mac-build"
OUTPUT_DIR="${WORK_DIR}/output"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

# =============================================================================
# Step 1: Download and extract Firebase xcframeworks
# =============================================================================
echo "==> [1/3] Downloading Firebase ${FIREBASE_VERSION}..."
curl -L --retry 3 -o "${WORK_DIR}/Firebase.zip" \
  "https://github.com/firebase/firebase-ios-sdk/releases/download/${FIREBASE_VERSION}/Firebase.zip"

echo "==> Extracting Firebase xcframeworks..."
unzip -q "${WORK_DIR}/Firebase.zip" -d "${WORK_DIR}/firebase"

FIREBASE_XCFRAMEWORKS=(
  "FirebaseAnalytics/FirebaseCore.xcframework"
  "FirebaseAnalytics/FirebaseCoreInternal.xcframework"
  "FirebaseAnalytics/FirebaseInstallations.xcframework"
  "FirebaseAnalytics/GoogleUtilities.xcframework"
  "FirebaseAnalytics/FBLPromises.xcframework"
  "FirebaseAnalytics/nanopb.xcframework"
  "FirebaseAuth/FirebaseAuth.xcframework"
  "FirebaseAuth/FirebaseAppCheckInterop.xcframework"
  "FirebaseAuth/FirebaseAuthInterop.xcframework"
  "FirebaseAuth/FirebaseCoreExtension.xcframework"
)

for fw in "${FIREBASE_XCFRAMEWORKS[@]}"; do
  name=$(basename "${fw}")
  echo "  Copying ${name}"
  cp -R "${WORK_DIR}/firebase/Firebase/${fw}" "${OUTPUT_DIR}/${name}"
done

echo "  Done — ${#FIREBASE_XCFRAMEWORKS[@]} Firebase xcframeworks copied."

# =============================================================================
# Step 2: Build GoogleSignIn from source for macOS (arm64 + x86_64)
# =============================================================================
echo ""
echo "==> [2/3] Building GoogleSignIn ${GOOGLESIGNIN_VERSION} for macOS..."

BUILDER_DIR="${WORK_DIR}/builder"
mkdir -p "${BUILDER_DIR}/Sources"

# Static library product — SPM merges all transitive deps into one .a
cat > "${BUILDER_DIR}/Package.swift" << EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Builder",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "GoogleSignInLib", type: .static, targets: ["GoogleSignInLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", exact: "${GOOGLESIGNIN_VERSION}"),
    ],
    targets: [
        .target(
            name: "GoogleSignInLib",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ],
            path: "Sources"
        ),
    ]
)
EOF

cat > "${BUILDER_DIR}/Sources/Placeholder.swift" << 'SRCEOF'
import Foundation
SRCEOF

echo "  Resolving dependencies..."
swift package --package-path "${BUILDER_DIR}" resolve 2>&1 | tail -5

echo "  Building for arm64..."
swift build -c release \
  --product GoogleSignInLib \
  --triple arm64-apple-macosx \
  --package-path "${BUILDER_DIR}" \
  --scratch-path "${WORK_DIR}/build-arm64" 2>&1 | tail -5

echo "  Building for x86_64..."
swift build -c release \
  --product GoogleSignInLib \
  --triple x86_64-apple-macosx \
  --package-path "${BUILDER_DIR}" \
  --scratch-path "${WORK_DIR}/build-x86_64" 2>&1 | tail -5

echo "  Done — both architectures built."

# =============================================================================
# Step 3: Create GoogleSignIn.xcframework
# =============================================================================
echo ""
echo "==> [3/3] Creating GoogleSignIn.xcframework..."

ARM64_LIB="${WORK_DIR}/build-arm64/arm64-apple-macosx/release/libGoogleSignInLib.a"
X86_LIB="${WORK_DIR}/build-x86_64/x86_64-apple-macosx/release/libGoogleSignInLib.a"
CHECKOUTS="${WORK_DIR}/build-arm64/checkouts"

if [ ! -f "${ARM64_LIB}" ]; then
  echo "ERROR: arm64 lib not found at ${ARM64_LIB}"
  echo "Contents of build-arm64 release dir:"
  ls -la "${WORK_DIR}/build-arm64/arm64-apple-macosx/release/" 2>/dev/null || echo "  dir not found"
  find "${WORK_DIR}/build-arm64" -name "*.a" 2>/dev/null || echo "  no .a files found"
  exit 1
fi

if [ ! -f "${X86_LIB}" ]; then
  echo "ERROR: x86_64 lib not found at ${X86_LIB}"
  exit 1
fi

# Collect GoogleSignIn public headers
HEADER_SRC="${CHECKOUTS}/GoogleSignIn-iOS/GoogleSignIn/Sources/Public/GoogleSignIn"
HEADERS_DIR="${WORK_DIR}/headers"
mkdir -p "${HEADERS_DIR}"

if [ -d "${HEADER_SRC}" ]; then
  find "${HEADER_SRC}" -name '*.h' -exec cp {} "${HEADERS_DIR}/" \;
  echo "  Copied $(ls "${HEADERS_DIR}" | wc -l | tr -d ' ') public headers"
else
  echo "WARNING: GoogleSignIn public headers not found at ${HEADER_SRC}"
  echo "  Searching checkouts..."
  find "${CHECKOUTS}" -path "*/GoogleSignIn/Sources/Public/*" -name "*.h" -exec cp {} "${HEADERS_DIR}/" \; 2>/dev/null || true
fi

# Generate module map
cat > "${HEADERS_DIR}/module.modulemap" << 'MMEOF'
module GoogleSignIn {
    umbrella header "GoogleSignIn.h"
    export *
}
MMEOF

# Create universal (fat) binary — xcframework expects one lib per platform
UNIVERSAL_LIB="${WORK_DIR}/universal/libGoogleSignIn.a"
mkdir -p "${WORK_DIR}/universal"
lipo -create "${ARM64_LIB}" "${X86_LIB}" -output "${UNIVERSAL_LIB}"

# Create xcframework with universal macOS binary
xcodebuild -create-xcframework \
  -library "${UNIVERSAL_LIB}" \
  -headers "${HEADERS_DIR}" \
  -output "${OUTPUT_DIR}/GoogleSignIn.xcframework"

echo "  Created GoogleSignIn.xcframework"

# Also copy the GoogleSignIn resource bundle if it exists
BUNDLE_ARM64="${WORK_DIR}/build-arm64/arm64-apple-macosx/release/GoogleSignIn_GoogleSignIn.bundle"
if [ -d "${BUNDLE_ARM64}" ]; then
  cp -R "${BUNDLE_ARM64}" "${OUTPUT_DIR}/GoogleSignIn_GoogleSignIn.bundle"
  echo "  Copied GoogleSignIn resource bundle"
fi

# =============================================================================
# Package everything
# =============================================================================
echo ""
echo "==> Packaging..."

echo "  xcframeworks in output:"
ls -1 "${OUTPUT_DIR}" | grep '\.xcframework$' | while read -r fw; do
  echo "    ${fw}"
done

cd "${OUTPUT_DIR}"
# -y preserves symbolic links (critical for macOS versioned frameworks)
zip -r -q -y "${WORK_DIR}/firebase-mac-xcframeworks.zip" .

CHECKSUM=$(swift package compute-checksum "${WORK_DIR}/firebase-mac-xcframeworks.zip" 2>/dev/null || shasum -a 256 "${WORK_DIR}/firebase-mac-xcframeworks.zip" | awk '{print $1}')
SIZE=$(du -h "${WORK_DIR}/firebase-mac-xcframeworks.zip" | awk '{print $1}')

echo ""
echo "========================================="
echo "Build complete!"
echo "Output: ${WORK_DIR}/firebase-mac-xcframeworks.zip (${SIZE})"
echo "SHA-256 checksum: ${CHECKSUM}"
echo "========================================="
