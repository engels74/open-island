# open-island — justfile
# Single entry point for local development and CI.
# All CI workflows call justfile recipes — never scripts directly.
#
# Usage:
#   just --list        Show all recipes
#   just build         Debug build
#   just test          Run all tests
#   just lint          Lint + format check

# ─── Configuration ───────────────────────────────────────────────────────────

scheme           := "OpenIsland"
package_dir      := "OpenIslandKit"
build_dir        := justfile_directory() / "build"
derived_data     := build_dir / "DerivedData"
export_path      := build_dir / "export"
release_dir      := justfile_directory() / "releases"
app_name         := "OpenIsland"
display_name     := "Open Island"

# Shared xcodebuild flags
xcode_common     := "-scheme " + scheme + " -derivedDataPath " + derived_data
xcode_sign       := "CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="

# ─── Build ───────────────────────────────────────────────────────────────────

# Build all targets (debug, ad-hoc signed)
build:
    xcodebuild build {{ xcode_common }} \
        -configuration Debug \
        {{ xcode_sign }}

# Build all targets (release, ad-hoc signed)
build-release:
    rm -rf "{{ export_path }}"
    mkdir -p "{{ export_path }}"
    xcodebuild build {{ xcode_common }} \
        -configuration Release \
        {{ xcode_sign }} \
        COPY_PHASE_STRIP=YES \
        STRIP_INSTALLED_PRODUCT=YES
    cp -R "{{ derived_data }}/Build/Products/Release/{{ display_name }}.app" "{{ export_path }}/"
    @echo ""
    @echo "App exported to: {{ export_path }}/{{ display_name }}.app"

# Resolve SPM dependencies
resolve:
    xcodebuild -resolvePackageDependencies {{ xcode_common }}

# ─── Package (SPM) ──────────────────────────────────────────────────────────

# Build SPM package independently (catches package-level issues)
build-package:
    cd {{ package_dir }} && swift build

# Run SPM package tests via swift test
test-package:
    cd {{ package_dir }} && swift test

# ─── Test ────────────────────────────────────────────────────────────────────

# Run all test suites (Xcode scheme tests + SPM package tests)
test:
    @echo "=== Running Xcode scheme tests ==="
    xcodebuild test {{ xcode_common }} \
        -configuration Debug \
        {{ xcode_sign }} \
        -parallel-testing-enabled YES \
        -resultBundlePath {{ build_dir }}/TestResults.xcresult
    @echo ""
    @echo "=== Running SPM package tests ==="
    just test-package
    @echo ""
    @echo "All tests passed."

# Run tests with CI-specific settings (no retry, result bundle)
test-ci:
    @echo "=== Running Xcode scheme tests (CI) ==="
    xcodebuild test {{ xcode_common }} \
        -configuration Debug \
        {{ xcode_sign }} \
        -parallel-testing-enabled YES \
        -retry-tests-on-failure NO \
        -resultBundlePath {{ build_dir }}/TestResults.xcresult
    @echo ""
    @echo "=== Running SPM package tests (CI) ==="
    cd {{ package_dir }} && swift test 2>&1
    @echo ""
    @echo "All CI tests passed."

# ─── Lint & Format ──────────────────────────────────────────────────────────

# Run SwiftFormat on all Swift files (auto-fix)
format:
    swiftformat .

# Check SwiftFormat without modifying files (CI-safe)
format-check:
    swiftformat --lint .

# Run SwiftLint in strict mode
lint:
    swiftlint lint --strict

# Run SwiftLint with auto-correct, then verify
lint-fix:
    swiftlint lint --fix
    swiftlint lint --strict

# Run all code quality checks (CI target)
quality: format-check lint
    @echo "Code quality checks passed."

# ─── Pre-commit ─────────────────────────────────────────────────────────────

# Install prek hooks
install-hooks:
    prek install --hook-type pre-commit

# Update all prek hook revisions to latest
update-hooks:
    prek autoupdate
    @echo ""
    @echo "Hook revisions updated. Review changes in .pre-commit-config.yaml"
    @echo "and commit if everything looks good."

# Run prek on all files (manual full check)
pre-commit:
    prek run --all-files

# ─── Release ─────────────────────────────────────────────────────────────────

# Create DMG from release build (skip notarization)
dmg: build-release
    ./scripts/create-release.sh --skip-notarization --skip-github --skip-website

# Full local release pipeline (notarize + DMG + GitHub)
release: build-release
    ./scripts/create-release.sh

# Generate Sparkle EdDSA signing keys
generate-keys:
    ./scripts/generate-keys.sh

# ─── Version ─────────────────────────────────────────────────────────────────

# Show current version from Xcode project
version:
    @agvtool what-marketing-version -terse1
    @echo -n "Build: " && agvtool what-version -terse

# Set marketing version (usage: just set-version 1.2.3)
set-version new_version:
    agvtool new-marketing-version {{ new_version }}
    @echo "Marketing version set to {{ new_version }}"

# Increment build number (timestamp-based)
bump-build:
    agvtool new-version -all "$(date +%Y%m%d%H%M)"
    @echo "Build number updated."

# ─── Utilities ───────────────────────────────────────────────────────────────

# Remove build artifacts, DerivedData, and test results
clean:
    rm -rf {{ build_dir }}
    rm -rf DerivedData
    rm -rf .build
    cd {{ package_dir }} && swift package clean 2>/dev/null || true
    @echo "Clean complete."

# Deep clean — also remove releases and Xcode caches
nuke: clean
    rm -rf {{ release_dir }}
    rm -rf ~/Library/Developer/Xcode/DerivedData/OpenIsland-*
    @echo "Nuke complete."

# Verify all required development tools are installed
check-tools:
    @echo "Checking required tools..."
    @command -v xcodebuild >/dev/null 2>&1 && echo "  ✓ xcodebuild" || echo "  ✗ xcodebuild (install Xcode)"
    @command -v swift      >/dev/null 2>&1 && echo "  ✓ swift"      || echo "  ✗ swift (install Xcode)"
    @command -v swiftformat >/dev/null 2>&1 && echo "  ✓ swiftformat" || echo "  ✗ swiftformat (brew install swiftformat)"
    @command -v swiftlint  >/dev/null 2>&1 && echo "  ✓ swiftlint"  || echo "  ✗ swiftlint (brew install swiftlint)"
    @command -v just       >/dev/null 2>&1 && echo "  ✓ just"       || echo "  ✗ just (brew install just)"
    @command -v prek >/dev/null 2>&1 && echo "  ✓ prek" || echo "  ✗ prek (go install github.com/j178/prek@latest)"
    @command -v gh         >/dev/null 2>&1 && echo "  ✓ gh"         || echo "  ✗ gh (brew install gh)"
    @command -v create-dmg >/dev/null 2>&1 && echo "  ✓ create-dmg" || echo "  ✗ create-dmg (brew install create-dmg) [optional]"
    @echo ""
    @echo "Swift version:"
    @swift --version 2>/dev/null | head -1
    @echo "Xcode version:"
    @xcodebuild -version 2>/dev/null | head -1
