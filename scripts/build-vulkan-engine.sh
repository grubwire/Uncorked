#!/usr/bin/env bash
#
# build-vulkan-engine.sh — rebuild the Crosswire engine's Wine with Vulkan support
#
# Background: the shipping engine is built with --without-vulkan, so DXVK
# cannot function and 3D Windows games fail to render. This script
# rebuilds wine64 (and wow64) in /tmp/wine-build/wine-src with Vulkan
# enabled, signs the resulting Mach-O binaries inside-out (Phase 1 ad-hoc),
# and swaps them into the installed engine. Existing CW patches (24945,
# 25719, 18947, 23427, 22131, 20760, 20186, 23427, 24256) are preserved
# because we build the existing patched tree, not a fresh clone.
#
# Prerequisites (verified by check_prereqs):
#   brew install bison mingw-w64 vulkan-headers vulkan-loader
#   /tmp/wine-build/wine-src is the patched 11.9 tree
#
# *** KNOWN BLOCKER ON APPLE SILICON ***
# Homebrew's vulkan-loader on Apple Silicon ships an arm64-only
# libvulkan.dylib. The existing Crosswire engine is x86_64 (running under
# Rosetta), so configure with `--host=x86_64-apple-darwin` fails to link
# against the arm64 brew libvulkan. Two paths forward, pick one before
# running this script:
#
#   (A) Install the LunarG Vulkan SDK for macOS, which ships a universal
#       (arm64 + x86_64) libvulkan.dylib and MoltenVK. Point pkg-config /
#       linker at /usr/local/lib (or wherever the SDK installs to) before
#       configure.
#
#   (B) Pivot the entire engine to arm64-native, which removes the Rosetta
#       step. Needs llvm-mingw (brew install llvm-mingw) for PE
#       cross-compilation, and a from-scratch rebuild of every Mach-O .so
#       in dlls/ — not a 2-hour job.
#
# Until one of those is done this script's configure_step will fail with
# "libvulkan and libMoltenVK 64-bit development files not found."
#
# Runtime: about 1.5–2 hours on M1/M2 for a fresh full build.
# Safe to re-run: build dir is rebuilt from scratch each invocation.
# Safe to abort: existing engine is only touched in the final swap step.

set -euo pipefail

BUILD_DIR="/tmp/wine-build/build-vulkan"
SRC_DIR="/tmp/wine-build/wine-src"
ENGINE_DIR="$HOME/Library/Application Support/app.Crosswire.Crosswire/Engine"
LOG_FILE="/tmp/crosswire-overnight/vulkan-build-$(date +%Y%m%dT%H%M%S).log"

mkdir -p "$(dirname "$LOG_FILE")"

log() { printf '\n=== %s ===\n' "$*" | tee -a "$LOG_FILE"; }

check_prereqs() {
    log "Checking prerequisites"
    local missing=0
    for cmd in /opt/homebrew/opt/bison/bin/bison /opt/homebrew/opt/mingw-w64/bin/x86_64-w64-mingw32-gcc; do
        if [[ ! -x "$cmd" ]]; then
            echo "MISSING: $cmd" | tee -a "$LOG_FILE"
            missing=1
        fi
    done
    if ! PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig" pkg-config --exists vulkan; then
        echo "MISSING: pkg-config can't find vulkan (brew install vulkan-headers vulkan-loader)" | tee -a "$LOG_FILE"
        missing=1
    fi
    if [[ ! -d "$SRC_DIR" ]]; then
        echo "MISSING: $SRC_DIR — wine source tree not present" | tee -a "$LOG_FILE"
        missing=1
    fi
    if [[ ! -d "$ENGINE_DIR/bin" ]]; then
        echo "MISSING: $ENGINE_DIR/bin — engine not installed" | tee -a "$LOG_FILE"
        missing=1
    fi
    if (( missing > 0 )); then
        echo "Run: brew install bison mingw-w64 vulkan-headers vulkan-loader" >&2
        exit 1
    fi
    echo "All prerequisites present." | tee -a "$LOG_FILE"
}

configure_step() {
    # The existing engine is x86_64 (running under Rosetta on Apple Silicon).
    # We match the host triple so the rebuilt binaries are drop-in replacements,
    # and so x86_64-w64-mingw32 (the only mingw available locally) satisfies
    # the PE cross-compilation requirement.
    log "Configuring Wine with Vulkan (build dir: $BUILD_DIR)"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/mingw-w64/bin:/opt/homebrew/bin:$PATH" \
    PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig" \
        "$SRC_DIR/configure" \
            --host=x86_64-apple-darwin \
            --enable-win64 \
            --with-vulkan \
            --without-x \
            --without-freetype \
            --disable-tests 2>&1 | tee -a "$LOG_FILE"
    if ! grep -q "SONAME_LIBVULKAN" "$BUILD_DIR/include/config.h"; then
        echo "Configure ran but Vulkan was NOT detected — see $LOG_FILE" >&2
        exit 1
    fi
    echo "Vulkan detected in config.h. OK." | tee -a "$LOG_FILE"
}

build_step() {
    log "Building Wine (this is the slow step: ~1.5–2 hours)"
    cd "$BUILD_DIR"
    PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/mingw-w64/bin:/opt/homebrew/bin:$PATH" \
    PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig" \
        make -j"$(sysctl -n hw.ncpu)" 2>&1 | tee -a "$LOG_FILE"
}

sign_step() {
    log "Signing rebuilt Mach-O binaries (ad-hoc, Phase 1)"
    # Sign each .dylib and each Mach-O .so/executable individually.
    # Inside-out: leaf .dylibs first, then the wrappers.
    cd "$BUILD_DIR"
    find . -type f \( -name '*.dylib' -o -name '*.so' \) -print0 | \
        while IFS= read -r -d '' f; do
            if file "$f" | grep -q "Mach-O"; then
                codesign --force --sign - "$f" 2>>"$LOG_FILE" || true
            fi
        done
    # Sign wine64 / wineserver / wineboot
    for f in wine64 server/wineserver loader/wine64; do
        if [[ -f "$f" ]] && file "$f" | grep -q "Mach-O"; then
            codesign --force --sign - "$f" 2>>"$LOG_FILE" || true
        fi
    done
}

swap_step() {
    log "Swapping rebuilt binaries into engine (backups end .pre-vulkan)"
    cd "$BUILD_DIR"

    # Back up the existing wine64 + wineserver before clobbering.
    for original in "$ENGINE_DIR/bin/wine64" "$ENGINE_DIR/bin/wineserver"; do
        if [[ -f "$original" && ! -f "$original.pre-vulkan" ]]; then
            cp "$original" "$original.pre-vulkan"
            echo "  backed up: $original.pre-vulkan" | tee -a "$LOG_FILE"
        fi
    done

    # Copy new wine64 and wineserver in place.
    if [[ -f "wine64" ]]; then
        cp -f "wine64" "$ENGINE_DIR/bin/wine64"
        echo "  installed: $ENGINE_DIR/bin/wine64" | tee -a "$LOG_FILE"
    fi
    if [[ -f "server/wineserver" ]]; then
        cp -f "server/wineserver" "$ENGINE_DIR/bin/wineserver"
        echo "  installed: $ENGINE_DIR/bin/wineserver" | tee -a "$LOG_FILE"
    fi

    # winevulkan PE DLL (the new piece that DXVK depends on).
    local winevulkan="dlls/winevulkan/winevulkan.dll"
    if [[ -f "$winevulkan" ]]; then
        local target="$ENGINE_DIR/lib/wine/x86_64-windows/winevulkan.dll"
        if [[ -f "$target" && ! -f "$target.pre-vulkan" ]]; then
            cp "$target" "$target.pre-vulkan"
        fi
        cp -f "$winevulkan" "$target"
        echo "  installed: $target" | tee -a "$LOG_FILE"
    fi
}

verify_step() {
    log "Verifying Vulkan is now reported by Wine"
    PATH="$ENGINE_DIR/bin:$PATH" \
        "$ENGINE_DIR/bin/Crosswire64" winecfg --help 2>&1 | grep -i vulkan | tee -a "$LOG_FILE" || true
    echo "Tip: launch a DXVK-using app and check the run log for 'winevulkan' / 'MoltenVK'." | tee -a "$LOG_FILE"
}

main() {
    echo "Vulkan engine rebuild — log: $LOG_FILE"
    check_prereqs
    configure_step
    build_step
    sign_step
    swap_step
    verify_step
    log "Done. Backups end .pre-vulkan; to revert: mv X.pre-vulkan X"
}

main "$@"
