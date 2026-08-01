#!/data/data/com.termux/files/usr/bin/sh

# Backward-compatible wrapper.
# Canonical script is in termux_boot/90-runit-guard.sh.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$SCRIPT_DIR/termux_boot/90-runit-guard.sh" "$@"
