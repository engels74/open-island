#!/bin/bash
# ─── Worktree Setup Script ─────────────────────────────────────────────────
# Prepares a new git worktree for local development of Open Island.
# Idempotent — safe to re-run at any time.
#
# Expected variables (set by the caller):
#   MAIN_CHECKOUT  — absolute path to the main repo clone
#   WORKTREE_PATH  — absolute path to the new worktree directory
#   BRANCH_NAME    — branch name for this worktree
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Validation ─────────────────────────────────────────────────────────────

if [[ -z "${MAIN_CHECKOUT:-}" || -z "${WORKTREE_PATH:-}" || -z "${BRANCH_NAME:-}" ]]; then
    echo "ERROR: MAIN_CHECKOUT, WORKTREE_PATH, and BRANCH_NAME must all be set."
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Open Island — Worktree Setup                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Main checkout : $MAIN_CHECKOUT"
echo "  Worktree path : $WORKTREE_PATH"
echo "  Branch        : $BRANCH_NAME"
echo ""

cd "$WORKTREE_PATH"

# ─── Helper functions ───────────────────────────────────────────────────────

info()  { echo "▸ $*"; }
warn()  { echo "⚠ $*"; }
ok()    { echo "✓ $*"; }

copy_if_exists() {
    local file="$1"
    if [[ -f "$MAIN_CHECKOUT/$file" ]]; then
        cp "$MAIN_CHECKOUT/$file" "$WORKTREE_PATH/$file"
        ok "Copied $file"
    fi
}

# ─── 1. Config & environment files ─────────────────────────────────────────

info "Copying config & environment files from main checkout..."

config_files=(
    .env
    .env.local
    .env.development
    .env.development.local
    .envrc
    .tool-versions
    .nvmrc
    .node-version
    .python-version
    .swiftformat
    .swiftlint.yml
    .pre-commit-config.yaml
    .editorconfig
)

copied=0
for f in "${config_files[@]}"; do
    if [[ -f "$MAIN_CHECKOUT/$f" ]]; then
        cp "$MAIN_CHECKOUT/$f" "$WORKTREE_PATH/$f"
        ((copied++))
    fi
done

if (( copied > 0 )); then
    ok "Copied $copied config file(s)"
else
    info "No config/env files found to copy (this is normal for early-stage projects)"
fi

# ─── 2. Ignored but required directories ───────────────────────────────────

info "Linking/copying gitignored directories needed at dev time..."

# Symlink DerivedData cache if it exists (large, read-heavy, safe to share)
if [[ -d "$MAIN_CHECKOUT/build/DerivedData" ]]; then
    mkdir -p "$WORKTREE_PATH/build"
    if [[ ! -e "$WORKTREE_PATH/build/DerivedData" ]]; then
        # NOTE: Each worktree should have its own DerivedData to avoid Xcode
        # conflicts. We skip symlinking — Xcode will create it on first build.
        info "Skipping DerivedData symlink (Xcode manages per-worktree)"
    fi
fi

# Copy xcuserdata schemes/settings if they exist (small, may be mutated)
find "$MAIN_CHECKOUT" -maxdepth 3 -type d -name "xcuserdata" 2>/dev/null | while read -r ud; do
    rel="${ud#"$MAIN_CHECKOUT/"}"
    target_dir="$WORKTREE_PATH/$(dirname "$rel")"
    if [[ -d "$target_dir" && ! -d "$WORKTREE_PATH/$rel" ]]; then
        cp -R "$ud" "$WORKTREE_PATH/$rel"
        ok "Copied $rel"
    fi
done

# Copy Sparkle signing keys if present (needed for release builds)
if [[ -d "$MAIN_CHECKOUT/keys" && ! -d "$WORKTREE_PATH/keys" ]]; then
    cp -R "$MAIN_CHECKOUT/keys" "$WORKTREE_PATH/keys"
    ok "Copied keys/ directory"
fi

# ─── 3. Dependency installation ─────────────────────────────────────────────

info "Resolving dependencies..."

# Swift Package Manager — resolve via Xcode or swift CLI
if [[ -f "$WORKTREE_PATH/Package.swift" ]]; then
    info "Resolving SPM dependencies (root Package.swift)..."
    swift package resolve 2>&1 && ok "SPM dependencies resolved (root)" || warn "SPM resolve failed for root package"
fi

# OpenIslandKit local package
if [[ -f "$WORKTREE_PATH/OpenIslandKit/Package.swift" ]]; then
    info "Resolving SPM dependencies (OpenIslandKit)..."
    (cd "$WORKTREE_PATH/OpenIslandKit" && swift package resolve 2>&1) \
        && ok "SPM dependencies resolved (OpenIslandKit)" \
        || warn "SPM resolve failed for OpenIslandKit"
fi

# Xcode project-level SPM resolution via justfile (if Xcode project exists)
if ls "$WORKTREE_PATH"/*.xcodeproj 1>/dev/null 2>&1; then
    if command -v just >/dev/null 2>&1; then
        info "Resolving Xcode package dependencies..."
        just resolve 2>&1 && ok "Xcode SPM dependencies resolved" || warn "Xcode SPM resolve failed (non-fatal)"
    else
        warn "just not found — skipping Xcode SPM resolution (brew install just)"
    fi
fi

# ─── 4. Pre-commit hooks (prek) ───────────────────────────────────────────

if [[ -f "$WORKTREE_PATH/.pre-commit-config.yaml" ]]; then
    if command -v prek >/dev/null 2>&1; then
        info "Installing prek hooks..."
        prek install --hook-type pre-commit --hook-type pre-push 2>&1 \
            && ok "prek hooks installed" \
            || warn "prek hook installation failed"
    else
        warn "prek not found — skipping hook installation (brew install prek)"
    fi
fi

# ─── 5. Local services (Docker Compose) ────────────────────────────────────

# This project is a native macOS app and does not use Docker.
# Uncomment below if Docker services are added in the future:
#
# if [[ -f "$WORKTREE_PATH/docker-compose.yml" ]] || [[ -f "$WORKTREE_PATH/compose.yml" ]]; then
#     info "Docker Compose file detected."
#     info "To start services: docker compose up -d"
# fi

# ─── 6. Build / codegen steps ──────────────────────────────────────────────

# No codegen required for this project currently.
# If Xcode project exists, do a quick SPM build to prime caches:
if [[ -f "$WORKTREE_PATH/OpenIslandKit/Package.swift" ]]; then
    if command -v swift >/dev/null 2>&1; then
        info "Building OpenIslandKit to prime SPM caches..."
        (cd "$WORKTREE_PATH/OpenIslandKit" && swift build 2>&1) \
            && ok "OpenIslandKit build succeeded" \
            || warn "OpenIslandKit build failed (you can build manually later)"
    fi
fi

# ─── 7. Sanity check ───────────────────────────────────────────────────────

echo ""
echo "─── Environment Check ──────────────────────────────────────────"

if command -v just >/dev/null 2>&1; then
    just check-tools 2>&1
else
    # Inline fallback if just isn't available
    for tool in xcodebuild swift swiftformat swiftlint just prek gh; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
    echo ""
    swift --version 2>/dev/null | head -1 || true
    xcodebuild -version 2>/dev/null | head -1 || true
fi

echo ""
echo "─── Worktree Ready ─────────────────────────────────────────────"
echo ""
echo "  Branch : $BRANCH_NAME"
echo "  Path   : $WORKTREE_PATH"
echo ""
echo "  Quick start:"
echo "    cd $WORKTREE_PATH"
echo "    just build          # Debug build"
echo "    just test           # Run all tests"
echo "    just check-tools    # Verify dev tools"
echo ""
