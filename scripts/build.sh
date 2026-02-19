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
#     GoogleSignIn, AppAuthCore, GTMAppAuth, GTMSessionFetcher
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
# Step 2: Build GoogleSignIn + deps from source for macOS (arm64 + x86_64)
# =============================================================================
echo ""
echo "==> [2/3] Building GoogleSignIn ${GOOGLESIGNIN_VERSION} for macOS..."

BUILDER_DIR="${WORK_DIR}/builder"
mkdir -p "${BUILDER_DIR}/Sources"

# Static library product — forces SPM to create .a and preserves per-target .o files
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
# Step 3: Create xcframeworks from individual target .o files
# =============================================================================
echo ""
echo "==> [3/3] Creating xcframeworks..."

ARM64_REL="${WORK_DIR}/build-arm64/arm64-apple-macosx/release"
X86_REL="${WORK_DIR}/build-x86_64/x86_64-apple-macosx/release"
CHECKOUTS="${WORK_DIR}/build-arm64/checkouts"
STAGING="${WORK_DIR}/staging"

# Helper: create xcframework using a framework bundle (avoids module.modulemap conflicts)
# Usage: make_xcframework <xcf-name> <build-subdir> <header-path-relative-to-checkouts>
make_xcframework() {
  local name="$1"
  local build_dir="$2"
  local header_rel="$3"

  local arm64_dir="${ARM64_REL}/${build_dir}"
  local x86_dir="${X86_REL}/${build_dir}"

  echo "  Creating ${name}.xcframework..."

  if [ ! -d "${arm64_dir}" ]; then
    echo "    WARNING: arm64 build dir not found: ${arm64_dir}"
    return 1
  fi

  rm -rf "${STAGING}"
  mkdir -p "${STAGING}/arm64" "${STAGING}/x86_64"

  # Create per-arch static libraries from .o files
  find "${arm64_dir}" -name '*.o' -print0 | xargs -0 ar rcs "${STAGING}/arm64/lib${name}.a"
  find "${x86_dir}" -name '*.o' -print0 | xargs -0 ar rcs "${STAGING}/x86_64/lib${name}.a"

  # Create universal binary
  lipo -create "${STAGING}/arm64/lib${name}.a" "${STAGING}/x86_64/lib${name}.a" \
    -output "${STAGING}/lib${name}.a"

  # Build a framework bundle — avoids the shared include/module.modulemap conflict
  local fw="${STAGING}/${name}.framework"
  mkdir -p "${fw}/Headers" "${fw}/Modules"

  # Binary
  cp "${STAGING}/lib${name}.a" "${fw}/${name}"

  # Headers
  if [ -n "${header_rel}" ] && [ -d "${CHECKOUTS}/${header_rel}" ]; then
    find "${CHECKOUTS}/${header_rel}" -name '*.h' -exec cp {} "${fw}/Headers/" \;
  fi

  # Module map
  local umbrella=""
  if [ -f "${fw}/Headers/${name}.h" ]; then
    umbrella="umbrella header \"${name}.h\""
  else
    umbrella="umbrella \".\""
  fi

  cat > "${fw}/Modules/module.modulemap" << MMEOF
framework module ${name} {
    ${umbrella}
    export *
}
MMEOF

  xcodebuild -create-xcframework \
    -framework "${fw}" \
    -output "${OUTPUT_DIR}/${name}.xcframework" 2>&1 | grep -v "^$" || true

  rm -rf "${STAGING}"
}

# -- GTMSessionFetcher --
# Named "GTMSessionFetcher" (not GTMSessionFetcherCore) because:
#   1. Headers use #include <GTMSessionFetcher/GTMSessionFetcher.h>
#   2. FirebaseAuth.swiftinterface requires `import GTMSessionFetcher`
#   3. GTMAppAuth headers use #import <GTMSessionFetcher/GTMSessionFetcher.h>
make_xcframework "GTMSessionFetcher" "GTMSessionFetcherCore.build" \
  "gtm-session-fetcher/Sources/Core/Public/GTMSessionFetcher"

# -- AppAuthCore --
make_xcframework "AppAuthCore" "AppAuthCore.build" \
  "AppAuth-iOS/Sources/AppAuthCore"

# -- GTMAppAuth --
make_xcframework "GTMAppAuth" "GTMAppAuth.build" \
  "GTMAppAuth/GTMAppAuth/Sources/Public/GTMAppAuth"

# -- GoogleSignIn --
make_xcframework "GoogleSignIn" "GoogleSignIn.build" \
  "GoogleSignIn-iOS/GoogleSignIn/Sources/Public/GoogleSignIn"

# Copy GoogleSignIn resource bundle
BUNDLE_ARM64="${ARM64_REL}/GoogleSignIn_GoogleSignIn.bundle"
if [ -d "${BUNDLE_ARM64}" ]; then
  cp -R "${BUNDLE_ARM64}" "${OUTPUT_DIR}/GoogleSignIn_GoogleSignIn.bundle"
  echo "  Copied GoogleSignIn resource bundle"
fi

echo "  Done."

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
