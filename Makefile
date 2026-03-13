# open-island — Makefile
# Single entry point for local development and CI.
# All CI workflows call Makefile targets — never scripts directly.
#
# Usage:
#   make help          Show all targets
#   make build         Debug build
#   make test          Run all tests
#   make lint          Lint + format check
#   make release       Full release pipeline (local)

# ─── Configuration ───────────────────────────────────────────────────────────

SCHEME           := OpenIsland
PACKAGE_DIR      := OpenIslandKit
PROJECT_DIR      := $(shell pwd)
BUILD_DIR        := $(PROJECT_DIR)/build
DERIVED_DATA     := $(BUILD_DIR)/DerivedData
EXPORT_PATH      := $(BUILD_DIR)/export
RELEASE_DIR      := $(PROJECT_DIR)/releases
APP_NAME         := OpenIsland
DISPLAY_NAME     := Open Island

# Xcode build settings shared across targets
XCODE_COMMON     := -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)
XCODE_SIGN       := CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

# Detect xcpretty for cleaner output
XCPRETTY         := $(shell command -v xcpretty 2>/dev/null)
ifdef XCPRETTY
  PIPE := | xcpretty
else
  PIPE :=
endif

# ─── Help ────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ─── Build ───────────────────────────────────────────────────────────────────

.PHONY: build
build: ## Build all targets (debug, ad-hoc signed)
	xcodebuild build $(XCODE_COMMON) \
		-configuration Debug \
		$(XCODE_SIGN) \
		$(PIPE)

.PHONY: build-release
build-release: ## Build all targets (release, ad-hoc signed)
	@rm -rf "$(EXPORT_PATH)"
	@mkdir -p "$(EXPORT_PATH)"
	xcodebuild build $(XCODE_COMMON) \
		-configuration Release \
		$(XCODE_SIGN) \
		COPY_PHASE_STRIP=YES \
		STRIP_INSTALLED_PRODUCT=YES \
		$(PIPE)
	@cp -R "$(DERIVED_DATA)/Build/Products/Release/$(DISPLAY_NAME).app" "$(EXPORT_PATH)/"
	@echo ""
	@echo "App exported to: $(EXPORT_PATH)/$(DISPLAY_NAME).app"

.PHONY: resolve
resolve: ## Resolve SPM dependencies
	xcodebuild -resolvePackageDependencies $(XCODE_COMMON)

# ─── Package (SPM) ──────────────────────────────────────────────────────────

.PHONY: build-package
build-package: ## Build SPM package independently (catches package-level issues)
	cd $(PACKAGE_DIR) && swift build

.PHONY: test-package
test-package: ## Run SPM package tests via swift test
	cd $(PACKAGE_DIR) && swift test

# ─── Test ────────────────────────────────────────────────────────────────────

.PHONY: test
test: ## Run all test suites (Xcode scheme tests + SPM package tests)
	@echo "=== Running Xcode scheme tests ==="
	xcodebuild test $(XCODE_COMMON) \
		-configuration Debug \
		$(XCODE_SIGN) \
		-parallel-testing-enabled YES \
		-resultBundlePath $(BUILD_DIR)/TestResults.xcresult \
		$(PIPE)
	@echo ""
	@echo "=== Running SPM package tests ==="
	@$(MAKE) test-package
	@echo ""
	@echo "All tests passed."

.PHONY: test-ci
test-ci: ## Run tests with CI-specific settings (XML output, no retry)
	@echo "=== Running Xcode scheme tests (CI) ==="
	xcodebuild test $(XCODE_COMMON) \
		-configuration Debug \
		$(XCODE_SIGN) \
		-parallel-testing-enabled YES \
		-retry-tests-on-failure NO \
		-resultBundlePath $(BUILD_DIR)/TestResults.xcresult \
		$(PIPE)
	@echo ""
	@echo "=== Running SPM package tests (CI) ==="
	cd $(PACKAGE_DIR) && swift test 2>&1
	@echo ""
	@echo "All CI tests passed."

# ─── Lint & Format ──────────────────────────────────────────────────────────

.PHONY: format
format: ## Run SwiftFormat on all Swift files (auto-fix)
	swiftformat .

.PHONY: format-check
format-check: ## Check SwiftFormat without modifying files (CI-safe)
	swiftformat --lint .

.PHONY: lint
lint: ## Run SwiftLint in strict mode
	swiftlint lint --strict

.PHONY: lint-fix
lint-fix: ## Run SwiftLint with auto-correct
	swiftlint lint --fix
	swiftlint lint --strict

.PHONY: quality
quality: format-check lint ## Run all code quality checks (CI target)
	@echo "Code quality checks passed."

# ─── Pre-commit ─────────────────────────────────────────────────────────────

.PHONY: install-hooks
install-hooks: ## Install pre-commit hooks (pre-commit + pre-push)
	pre-commit install --hook-type pre-commit --hook-type pre-push

.PHONY: update-hooks
update-hooks: ## Update all pre-commit hook revisions to latest
	pre-commit autoupdate
	@echo ""
	@echo "Hook revisions updated. Review changes in .pre-commit-config.yaml"
	@echo "and commit if everything looks good."

.PHONY: pre-commit
pre-commit: ## Run pre-commit on all files (manual full check)
	pre-commit run --all-files

# ─── Release ─────────────────────────────────────────────────────────────────

.PHONY: dmg
dmg: build-release ## Create DMG from release build (skip notarization)
	./scripts/create-release.sh --skip-notarization --skip-github --skip-website

.PHONY: release
release: build-release ## Full local release pipeline (notarize + DMG + GitHub)
	./scripts/create-release.sh

.PHONY: generate-keys
generate-keys: ## Generate Sparkle EdDSA signing keys
	./scripts/generate-keys.sh

# ─── Version ─────────────────────────────────────────────────────────────────

.PHONY: version
version: ## Show current version from Xcode project
	@agvtool what-marketing-version -terse1
	@echo -n "Build: " && agvtool what-version -terse

.PHONY: set-version
set-version: ## Set marketing version (usage: make set-version V=1.2.3)
ifndef V
	$(error Usage: make set-version V=1.2.3)
endif
	agvtool new-marketing-version $(V)
	@echo "Marketing version set to $(V)"

.PHONY: bump-build
bump-build: ## Increment build number (timestamp-based)
	agvtool new-version -all $$(date +%Y%m%d%H%M)
	@echo "Build number updated."

# ─── Utilities ───────────────────────────────────────────────────────────────

.PHONY: clean
clean: ## Remove build artifacts, DerivedData, and test results
	rm -rf $(BUILD_DIR)
	rm -rf DerivedData
	rm -rf .build
	cd $(PACKAGE_DIR) && swift package clean 2>/dev/null || true
	@echo "Clean complete."

.PHONY: nuke
nuke: clean ## Deep clean — also remove releases and Xcode caches
	rm -rf $(RELEASE_DIR)
	rm -rf ~/Library/Developer/Xcode/DerivedData/OpenIsland-*
	@echo "Nuke complete."

.PHONY: check-tools
check-tools: ## Verify all required development tools are installed
	@echo "Checking required tools..."
	@command -v xcodebuild >/dev/null 2>&1 && echo "  ✓ xcodebuild" || echo "  ✗ xcodebuild (install Xcode)"
	@command -v swift      >/dev/null 2>&1 && echo "  ✓ swift"      || echo "  ✗ swift (install Xcode)"
	@command -v swiftformat >/dev/null 2>&1 && echo "  ✓ swiftformat" || echo "  ✗ swiftformat (brew install swiftformat)"
	@command -v swiftlint  >/dev/null 2>&1 && echo "  ✓ swiftlint"  || echo "  ✗ swiftlint (brew install swiftlint)"
	@command -v pre-commit >/dev/null 2>&1 && echo "  ✓ pre-commit" || echo "  ✗ pre-commit (brew install pre-commit)"
	@command -v gh         >/dev/null 2>&1 && echo "  ✓ gh"         || echo "  ✗ gh (brew install gh)"
	@command -v create-dmg >/dev/null 2>&1 && echo "  ✓ create-dmg" || echo "  ✗ create-dmg (brew install create-dmg) [optional]"
	@command -v xcpretty   >/dev/null 2>&1 && echo "  ✓ xcpretty"   || echo "  ✗ xcpretty (gem install xcpretty) [optional]"
	@echo ""
	@echo "Swift version:"
	@swift --version 2>/dev/null | head -1
	@echo "Xcode version:"
	@xcodebuild -version 2>/dev/null | head -1
