#!/bin/bash
# Build Open Island with ad-hoc signing.
# Prefer calling via: just build-release
# This script is also called directly by CI workflows.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
EXPORT_PATH="$BUILD_DIR/export"

SCHEME="OpenIsland"
DISPLAY_NAME="Open Island"

# ─── Version sync check ─────────────────────────────────────────────────────

check_version_sync() {
    local latest_tag current_version

    latest_tag=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null || true)
    latest_tag="${latest_tag#v}"

    if [ -n "$latest_tag" ]; then
        # agvtool reads MARKETING_VERSION from project.pbxproj — works with
        # both direct values and $(MARKETING_VERSION) variable references.
        current_version=$(cd "$PROJECT_DIR" && agvtool what-marketing-version -terse1 2>/dev/null) || true

        if [ -n "$current_version" ] && [ "$latest_tag" != "$current_version" ]; then
            echo "⚠️  Warning: Local version ($current_version) differs from latest tag ($latest_tag)"
            echo "   Run: just set-version $latest_tag"
            echo ""
        fi
    fi
}

# ─── SPM package resolution ─────────────────────────────────────────────────

resolve_packages() {
    echo "Resolving SPM dependencies..."
    xcodebuild -resolvePackageDependencies \
        -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA" \
        2>&1 | tail -1
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

check_version_sync

echo "=== Building Open Island (Ad-Hoc Signed) ==="
echo ""

# Clean previous export (keep DerivedData for incremental builds)
rm -rf "$EXPORT_PATH"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

cd "$PROJECT_DIR"

# Resolve packages explicitly — makes dependency failures visible early
# and allows CI to cache the resolution step separately.
resolve_packages

# Build with ad-hoc signing
echo "Building..."
XCODEBUILD_OPTS=(
    build
    -scheme "$SCHEME"
    -configuration Release
    -derivedDataPath "$DERIVED_DATA"
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
    COPY_PHASE_STRIP=YES
    STRIP_INSTALLED_PRODUCT=YES
)

if command -v xcpretty >/dev/null 2>&1; then
    xcodebuild "${XCODEBUILD_OPTS[@]}" | xcpretty
else
    xcodebuild "${XCODEBUILD_OPTS[@]}"
fi

# Copy app to expected location
APP_OUTPUT="$DERIVED_DATA/Build/Products/Release/$DISPLAY_NAME.app"

if [ ! -d "$APP_OUTPUT" ]; then
    echo "ERROR: Built app not found at $APP_OUTPUT"
    echo "Check the scheme name and build configuration."
    exit 1
fi

cp -R "$APP_OUTPUT" "$EXPORT_PATH/"

echo ""
echo "=== Build Complete ==="
echo "App exported to: $EXPORT_PATH/$DISPLAY_NAME.app"
echo ""
echo "Next: just dmg (or ./scripts/create-release.sh --skip-notarization)"
