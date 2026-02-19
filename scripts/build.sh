#!/bin/bash
set -euo pipefail

# =============================================================================
# Build Firebase + GoogleSignIn macOS xcframeworks
#
# Produces a single zip containing all xcframeworks needed for the Speechify
# Mac app's AuthenticationModule:
#
#   From Firebase.zip (pre-built):
#     FirebaseCore, FirebaseCoreInternal, FirebaseCoreExtension,
#     FirebaseInstallations, FirebaseAuth, FirebaseAppCheckInterop,
#     FirebaseAuthInterop, GoogleUtilities, FBLPromises, nanopb
#
#   Built from source for macOS:
#     GoogleSignIn, AppAuthCore, GTMAppAuth, GTMSessionFetcherCore
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
echo "==> [1/4] Downloading Firebase ${FIREBASE_VERSION}..."
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
# Step 2: Build GoogleSignIn + deps from source for macOS
# =============================================================================
echo ""
echo "==> [2/4] Building GoogleSignIn ${GOOGLESIGNIN_VERSION} from source..."

BUILDER_DIR="${WORK_DIR}/builder"
mkdir -p "${BUILDER_DIR}/Sources"

cat > "${BUILDER_DIR}/Package.swift" << EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Builder",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", exact: "${GOOGLESIGNIN_VERSION}"),
    ],
    targets: [
        .target(
            name: "Builder",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ],
            path: "Sources"
        ),
    ]
)
EOF

cat > "${BUILDER_DIR}/Sources/Placeholder.swift" << 'EOF'
import Foundation
EOF

echo "  Resolving dependencies..."
swift package --package-path "${BUILDER_DIR}" resolve 2>&1 | tail -5

echo "  Building for arm64..."
swift build -c release \
  --triple arm64-apple-macosx \
  --package-path "${BUILDER_DIR}" \
  --scratch-path "${WORK_DIR}/build-arm64" 2>&1 | tail -3

echo "  Building for x86_64..."
swift build -c release \
  --triple x86_64-apple-macosx \
  --package-path "${BUILDER_DIR}" \
  --scratch-path "${WORK_DIR}/build-x86_64" 2>&1 | tail -3

echo "  Done — both architectures built."

# =============================================================================
# Step 3: Create xcframeworks from built products
# =============================================================================
echo ""
echo "==> [3/4] Creating xcframeworks from built products..."

ARM64_BUILD="${WORK_DIR}/build-arm64/arm64-apple-macosx/release"
X86_BUILD="${WORK_DIR}/build-x86_64/x86_64-apple-macosx/release"
CHECKOUTS="${WORK_DIR}/build-arm64/checkouts"
UNIVERSAL_DIR="${WORK_DIR}/universal"

# Helper: create xcframework from a static library built for both architectures
create_xcframework() {
  local lib_name="$1"
  local header_source="$2"  # relative to checkouts dir, or "none"

  local arm64_lib="${ARM64_BUILD}/lib${lib_name}.a"
  local x86_lib="${X86_BUILD}/lib${lib_name}.a"

  if [ ! -f "${arm64_lib}" ]; then
    echo "  SKIP ${lib_name} — arm64 lib not found at ${arm64_lib}"
    return 1
  fi
  if [ ! -f "${x86_lib}" ]; then
    echo "  SKIP ${lib_name} — x86_64 lib not found at ${x86_lib}"
    return 1
  fi

  echo "  Creating ${lib_name}.xcframework..."

  rm -rf "${UNIVERSAL_DIR}"
  mkdir -p "${UNIVERSAL_DIR}"

  # Create universal (fat) binary
  lipo -create "${arm64_lib}" "${x86_lib}" -output "${UNIVERSAL_DIR}/lib${lib_name}.a"

  if [ "${header_source}" != "none" ] && [ -d "${CHECKOUTS}/${header_source}" ]; then
    # Copy headers to a clean directory (xcf creation needs a flat headers dir)
    local headers_dir="${UNIVERSAL_DIR}/Headers"
    mkdir -p "${headers_dir}"
    find "${CHECKOUTS}/${header_source}" -name '*.h' -exec cp {} "${headers_dir}/" \;

    xcodebuild -create-xcframework \
      -library "${UNIVERSAL_DIR}/lib${lib_name}.a" \
      -headers "${headers_dir}" \
      -output "${OUTPUT_DIR}/${lib_name}.xcframework" 2>&1 | grep -v "^$" || true
  else
    xcodebuild -create-xcframework \
      -library "${UNIVERSAL_DIR}/lib${lib_name}.a" \
      -output "${OUTPUT_DIR}/${lib_name}.xcframework" 2>&1 | grep -v "^$" || true
  fi

  rm -rf "${UNIVERSAL_DIR}"
}

# -- GTMSessionFetcherCore --
create_xcframework "GTMSessionFetcherCore" "gtm-session-fetcher/Sources/Core/Public"

# -- AppAuthCore --
# AppAuth-iOS has headers in Sources/AppAuthCore (public headers mixed in)
create_xcframework "AppAuthCore" "AppAuth-iOS/Sources/AppAuthCore"

# -- GTMAppAuth --
create_xcframework "GTMAppAuth" "GTMAppAuth/Sources/Public/GTMAppAuth/Include"

# -- GoogleSignIn --
create_xcframework "GoogleSignIn" "GoogleSignIn-iOS/GoogleSignIn/Sources/Public"

echo "  Done."

# =============================================================================
# Step 4: Package everything
# =============================================================================
echo ""
echo "==> [4/4] Packaging..."

# List what we have
echo "  xcframeworks in output:"
ls -1 "${OUTPUT_DIR}" | grep '\.xcframework$' | while read -r fw; do
  echo "    ${fw}"
done

cd "${OUTPUT_DIR}"
zip -r -q "${WORK_DIR}/firebase-mac-xcframeworks.zip" *.xcframework

CHECKSUM=$(swift package compute-checksum "${WORK_DIR}/firebase-mac-xcframeworks.zip" 2>/dev/null || shasum -a 256 "${WORK_DIR}/firebase-mac-xcframeworks.zip" | awk '{print $1}')
SIZE=$(du -h "${WORK_DIR}/firebase-mac-xcframeworks.zip" | awk '{print $1}')

echo ""
echo "========================================="
echo "Build complete!"
echo "Output: ${WORK_DIR}/firebase-mac-xcframeworks.zip (${SIZE})"
echo "SHA-256 checksum: ${CHECKSUM}"
echo "========================================="
