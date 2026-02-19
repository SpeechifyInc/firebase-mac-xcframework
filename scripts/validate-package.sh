#!/bin/bash
set -euo pipefail

# =============================================================================
# Validate Package.swift
#
# Checks:
#   1. Package.swift parses correctly (swift package dump-package)
#   2. Every wrapper target has a matching Sources/<dir>/dummy.swift
#
# This script does NOT run `swift build` — the binary target URLs won't
# resolve until the GitHub Release is actually created.
# =============================================================================

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_FILE="${REPO_ROOT}/Package.swift"
ERRORS=0

echo "==> Validating Package.swift..."

# --- Check 1: Package.swift parses ---
echo "  Checking swift package dump-package..."
if ! swift package --package-path "${REPO_ROOT}" dump-package > /dev/null 2>&1; then
  echo "  FAIL: Package.swift does not parse correctly"
  echo "  Output:"
  swift package --package-path "${REPO_ROOT}" dump-package 2>&1 | tail -20
  ERRORS=$((ERRORS + 1))
else
  echo "  OK: Package.swift parses correctly"
fi

# --- Check 2: Wrapper targets have Sources/ dirs ---
echo "  Checking Sources/ directories..."

# Extract wrapper target paths from Package.swift
# Looks for: path: "Sources/Foo"
while IFS= read -r line; do
  # Match lines like: path: "Sources/FirebaseCore"
  if [[ "${line}" =~ path:\ *\"Sources/([^\"]+)\" ]]; then
    target_dir="${BASH_REMATCH[1]}"
    dummy="${REPO_ROOT}/Sources/${target_dir}/dummy.swift"
    if [ ! -f "${dummy}" ]; then
      echo "  FAIL: Missing ${dummy}"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Sources/${target_dir}/dummy.swift exists"
    fi
  fi
done < "${PACKAGE_FILE}"

# --- Summary ---
echo ""
if [ "${ERRORS}" -gt 0 ]; then
  echo "VALIDATION FAILED (${ERRORS} error(s))"
  exit 1
else
  echo "All checks passed."
fi
