#!/bin/bash
set -euo pipefail

# =============================================================================
# Generate Package.swift from checksums.txt
#
# Usage:
#   TAG=firebase-12.8.0-googlesignin-7.0.0 bash scripts/generate-package.sh
#
# Reads checksums.txt (produced by build.sh) and writes Package.swift with
# .binaryTarget(url:checksum:) entries pointing to the GitHub Release assets.
#
# The dependency map below defines which binary targets each wrapper target
# needs. When a new xcframework is added to the build, just update the map.
# =============================================================================

TAG="${TAG:?TAG is required (e.g. firebase-12.8.0-googlesignin-7.0.0)}"
CHECKSUMS_FILE="${CHECKSUMS_FILE:-/tmp/firebase-mac-build/zips/checksums.txt}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${REPO_ROOT}/Package.swift"
BASE_URL="https://github.com/SpeechifyInc/firebase-mac-xcframework/releases/download/${TAG}"

if [ ! -f "${CHECKSUMS_FILE}" ]; then
  echo "ERROR: checksums.txt not found at ${CHECKSUMS_FILE}"
  echo "Run build.sh first to generate it."
  exit 1
fi

# =============================================================================
# Dependency map
#
# Each product is defined as: PRODUCT_NAME|dep1,dep2,dep3
# A dependency prefixed with "@" is a wrapper target reference (not a binary).
# =============================================================================

PRODUCT_MAP=(
  "FirebaseAuth|@FirebaseCoreTarget,FirebaseAuth,FirebaseCoreExtension,FirebaseInstallations,FirebaseAppCheckInterop,FirebaseAuthInterop,GTMSessionFetcher"
  "FirebaseCore|FirebaseCore,FirebaseCoreInternal,GoogleUtilities,FBLPromises,nanopb"
  "GoogleSignIn|GoogleSignIn,AppAuthCore,GTMAppAuth,GTMSessionFetcher"
)

# =============================================================================
# Helper: look up checksum for a given xcframework name
# =============================================================================
get_checksum() {
  local zip_name="$1.xcframework.zip"
  grep "^${zip_name} " "${CHECKSUMS_FILE}" | awk '{print $2}'
}

# =============================================================================
# Discover all xcframeworks from checksums.txt
# =============================================================================
echo "Discovered xcframeworks:"
grep '\.xcframework\.zip' "${CHECKSUMS_FILE}" | while read -r line; do
  echo "  ${line%% *}"
done
echo ""

# =============================================================================
# Ensure Sources/ directories exist for each wrapper target
# =============================================================================
for entry in "${PRODUCT_MAP[@]}"; do
  product="${entry%%|*}"
  target_dir="${REPO_ROOT}/Sources/${product}"
  dummy_file="${target_dir}/dummy.swift"
  if [ ! -f "${dummy_file}" ]; then
    echo "Creating ${dummy_file}"
    mkdir -p "${target_dir}"
    echo "// Placeholder — SPM requires at least one source file per target." > "${dummy_file}"
  fi
done

# =============================================================================
# Collect all unique binary targets needed
# =============================================================================
all_binaries=""
for entry in "${PRODUCT_MAP[@]}"; do
  deps="${entry#*|}"
  IFS=',' read -ra dep_arr <<< "${deps}"
  for dep in "${dep_arr[@]}"; do
    # Skip wrapper-target references
    if [[ "${dep}" != @* ]]; then
      all_binaries="${all_binaries} ${dep}"
    fi
  done
done

# Deduplicate and sort
sorted_binaries=$(echo "${all_binaries}" | tr ' ' '\n' | sort -u | grep -v '^$')

# Warn about missing checksums
for name in ${sorted_binaries}; do
  cs=$(get_checksum "${name}")
  if [ -z "${cs}" ]; then
    echo "WARNING: ${name} is in the dependency map but has no checksum in checksums.txt"
  fi
done

# =============================================================================
# Generate Package.swift
# =============================================================================

# --- Products block ---
products_block=""
for entry in "${PRODUCT_MAP[@]}"; do
  product="${entry%%|*}"
  products_block="${products_block}        .library(name: \"${product}\", targets: [\"${product}Target\"]),
"
done

# --- Wrapper targets block ---
wrapper_targets_block=""
for entry in "${PRODUCT_MAP[@]}"; do
  product="${entry%%|*}"
  deps="${entry#*|}"
  IFS=',' read -ra dep_arr <<< "${deps}"

  dep_lines=""
  for dep in "${dep_arr[@]}"; do
    if [[ "${dep}" == @* ]]; then
      dep_lines="${dep_lines}                \"${dep#@}\",
"
    else
      dep_lines="${dep_lines}                \"${dep}\",
"
    fi
  done

  wrapper_targets_block="${wrapper_targets_block}        .target(
            name: \"${product}Target\",
            dependencies: [
${dep_lines}            ],
            path: \"Sources/${product}\"
        ),
"
done

# --- Binary targets block ---
binary_targets_block=""
for name in ${sorted_binaries}; do
  checksum=$(get_checksum "${name}")
  if [ -z "${checksum}" ]; then
    continue
  fi
  binary_targets_block="${binary_targets_block}        .binaryTarget(
            name: \"${name}\",
            url: \"${BASE_URL}/${name}.xcframework.zip\",
            checksum: \"${checksum}\"
        ),
"
done

# --- Write the file ---
cat > "${OUTPUT}" << PKGEOF
// swift-tools-version: 5.9
import PackageDescription

// Auto-generated by scripts/generate-package.sh — do not edit manually.
// Tag: ${TAG}

let package = Package(
    name: "firebase-mac-xcframework",
    platforms: [.macOS(.v10_15)],
    products: [
${products_block}    ],
    targets: [
        // -- Wrapper targets (SPM requires at least one source file per target) --
${wrapper_targets_block}
        // -- Binary targets --
${binary_targets_block}    ]
)
PKGEOF

echo "Generated ${OUTPUT}"
echo "Tag: ${TAG}"
