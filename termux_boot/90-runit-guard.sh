#!/data/data/com.termux/files/usr/bin/sh

# Boot-time guard for runit startup races in Termux.
# For a short window, keep only one runsvdir and force sshd/crond supervision.

export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin:$PATH"
export SVDIR="/data/data/com.termux/files/usr/var/service"
export LOGDIR="/data/data/com.termux/files/usr/var/log"

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
SPESA_DIR="${SPESA_DIR:-$TERMUX_HOME/spesa}"
LOG_FILE="${LOG_FILE:-$SPESA_DIR/boot_runit_guard.log}"
LOCKFILE="${LOCKFILE:-/data/data/com.termux/files/usr/tmp/boot_runit_guard.lock}"

WINDOW_SECONDS="${WINDOW_SECONDS:-90}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3}"

SV_BIN="/data/data/com.termux/files/usr/bin/sv"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S %Z') | $*" >> "$LOG_FILE"
}

ensure_paths() {
  mkdir -p "$SPESA_DIR" 2>/dev/null || true
  mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null || true
  touch "$LOG_FILE" 2>/dev/null || exit 1
}

acquire_lock() {
  if (set -o noclobber; echo "$$" > "$LOCKFILE") 2>/dev/null; then
    trap 'rm -f "$LOCKFILE"' EXIT INT TERM
    return 0
  fi
  return 1
}

list_runsvdir_lines() {
  pgrep -a -x runsvdir 2>/dev/null
}

pick_keeper_pid() {
  MATCHING_PIDS=""

  while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue

    case "$LINE" in
      *" $SVDIR")
        PID="${LINE%% *}"
        case "$PID" in
          ''|*[!0-9]*) continue ;;
        esac

        MATCHING_PIDS="$MATCHING_PIDS $PID"
        ;;
    esac
  done <<EOF
$1
EOF

  set -- $MATCHING_PIDS
  case $# in
    0)
      echo ""
      return 1
      ;;
    1)
      echo "$1"
      return 0
      ;;
  esac

  KEEP_PID=""
  for PID in "$@"; do
    if [ -z "$KEEP_PID" ] || [ "$PID" -lt "$KEEP_PID" ]; then
      KEEP_PID="$PID"
    fi
  done

  echo "$KEEP_PID"
}

dedupe_runsvdir() {
  LINES="$(list_runsvdir_lines)"
  [ -n "$LINES" ] || return 0

  PIDS="$(printf '%s\n' "$LINES" | cut -d' ' -f1)"

  # shellcheck disable=SC2086
  set -- $PIDS
  COUNT=$#
  [ "$COUNT" -le 1 ] && return 0

  KEEP_PID="$(pick_keeper_pid "$LINES")" || KEEP_PID=""
  if [ -z "$KEEP_PID" ]; then
    log "Duplicate runsvdir detected but no instance matched SVDIR=$SVDIR; skipping kill. lines=$(printf '%s' "$LINES")"
    return 0
  fi

  log "Duplicate runsvdir detected: $PIDS | keeping PID=$KEEP_PID for SVDIR=$SVDIR"

  for PID in "$@"; do
    [ "$PID" = "$KEEP_PID" ] && continue
    kill "$PID" 2>/dev/null || true
  done

  sleep 2

  for PID in "$@"; do
    [ "$PID" = "$KEEP_PID" ] && continue
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null || true
    fi
  done

  AFTER="$(list_runsvdir_lines)"
  log "runsvdir after dedupe: ${AFTER:-none}"
}

ensure_services_up() {
  if [ -x "$SV_BIN" ]; then
    env SVDIR="$SVDIR" LOGDIR="$LOGDIR" "$SV_BIN" up sshd >> "$LOG_FILE" 2>&1 || true
    env SVDIR="$SVDIR" LOGDIR="$LOGDIR" "$SV_BIN" up crond >> "$LOG_FILE" 2>&1 || true
  else
    log "sv binary not found at $SV_BIN"
  fi
}

snapshot() {
  pgrep -a -f "runsvdir|runsv sshd|runsv crond|sshd -D -e|crond -n" >> "$LOG_FILE" 2>&1 || true
  ps -ef | grep -E "\[runsv\]|\[svlogd\]" | grep -E "defunct|Z" >> "$LOG_FILE" 2>&1 || true
}

main() {
  ensure_paths

  if ! acquire_lock; then
    log "Guard already running, exiting"
    exit 0
  fi

  log "===== BOOT RUNIT GUARD START ====="
  log "WINDOW_SECONDS=$WINDOW_SECONDS SLEEP_SECONDS=$SLEEP_SECONDS SVDIR=$SVDIR"

  ELAPSED=0
  while [ "$ELAPSED" -lt "$WINDOW_SECONDS" ]; do
    dedupe_runsvdir
    ensure_services_up
    snapshot

    sleep "$SLEEP_SECONDS"
    ELAPSED=$((ELAPSED + SLEEP_SECONDS))
  done

  log "===== BOOT RUNIT GUARD END ====="
}

main "$@"
