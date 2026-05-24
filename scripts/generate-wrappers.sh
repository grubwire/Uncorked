#!/bin/bash
# Generates the Crosswire-named entry-point wrapper scripts in Engine/bin/.
# Usage: scripts/generate-wrappers.sh <path-to-Engine-bin>
# Called by engine-bundle.yml after extracting the Gcenx archive.
set -euo pipefail

BIN="$1"

make_wrapper() {
    local name="$1"   # wrapper name (e.g. Crosswire64)
    local target="$2" # target binary (e.g. wine64)
    cat > "$BIN/$name" << EOF
#!/bin/sh
exec "\$(dirname "\$0")/$target" "\$@"
EOF
    chmod +x "$BIN/$name"
}

make_wrapper Crosswire64     wine64
make_wrapper Crosswireserver wineserver
make_wrapper Crosswireboot   wineboot
