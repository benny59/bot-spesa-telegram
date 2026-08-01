#!/data/data/com.termux/files/usr/bin/sh

# Deploy Termux boot scripts as symlinks to versioned files in this repo.

set -eu

REPO_DIR="${REPO_DIR:-/data/data/com.termux/files/home/spesa}"
SOURCE_DIR="${SOURCE_DIR:-$REPO_DIR/termux_boot}"
BOOT_DIR="${BOOT_DIR:-/data/data/com.termux/files/home/.termux/boot}"
DAZE_REPO_DIR="${DAZE_REPO_DIR:-/data/data/com.termux/files/home/daze}"
DAZE_BOOT_SCRIPT="${DAZE_BOOT_SCRIPT:-}"

disable_backup_executables() {
  find "$BOOT_DIR" -maxdepth 1 -type f \( -name '*.bak' -o -name '*.old' -o -name '*.orig' -o -name '*.save' \) -perm /111 2>/dev/null |
  while IFS= read -r FILE; do
    [ -n "$FILE" ] || continue
    chmod 600 "$FILE"
    echo "Disabled executable backup: $FILE"
  done
}

warn_extra_executables() {
  find "$BOOT_DIR" -maxdepth 1 -type f -perm /111 ! -name 'start-services' ! -name '90-runit-guard.sh' ! -name '10-daze-start' 2>/dev/null |
  while IFS= read -r FILE; do
    [ -n "$FILE" ] || continue
    echo "WARN: extra executable file in boot dir may also run: $FILE" >&2
  done
}

install_link() {
  SRC="$1"
  DST="$2"

  if [ ! -f "$SRC" ]; then
    echo "ERROR: missing source file: $SRC" >&2
    exit 1
  fi

  ln -sfn "$SRC" "$DST"
}

mkdir -p "$BOOT_DIR"

disable_backup_executables

chmod 700 "$SOURCE_DIR/start-services" "$SOURCE_DIR/90-runit-guard.sh"

install_link "$SOURCE_DIR/start-services" "$BOOT_DIR/start-services"
install_link "$SOURCE_DIR/90-runit-guard.sh" "$BOOT_DIR/90-runit-guard.sh"

# Optional: keep Daze boot script owned by the Daze repository.
if [ -z "$DAZE_BOOT_SCRIPT" ]; then
  for CANDIDATE in \
    "$DAZE_REPO_DIR/.termux/boot/10-daze-start" \
    "$DAZE_REPO_DIR/termux_boot/10-daze-start" \
    "$DAZE_REPO_DIR/scripts/10-daze-start"
  do
    if [ -f "$CANDIDATE" ]; then
      DAZE_BOOT_SCRIPT="$CANDIDATE"
      break
    fi
  done
fi

if [ -n "$DAZE_BOOT_SCRIPT" ] && [ -f "$DAZE_BOOT_SCRIPT" ]; then
  chmod 700 "$DAZE_BOOT_SCRIPT"
  install_link "$DAZE_BOOT_SCRIPT" "$BOOT_DIR/10-daze-start"
  echo "Linked Daze boot script: $DAZE_BOOT_SCRIPT"
else
  echo "WARN: Daze boot script not linked (set DAZE_BOOT_SCRIPT or DAZE_REPO_DIR)."
fi

echo "Boot links deployed:"
ls -la "$BOOT_DIR"
warn_extra_executables
