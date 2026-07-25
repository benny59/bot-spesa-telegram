#!/data/data/com.termux/files/usr/bin/sh

# Boot-time cron guard for Termux.
# Purpose: capture forensic info at boot and ensure crond is up.

export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin:$PATH"

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
SPESA_DIR="${SPESA_DIR:-$TERMUX_HOME/spesa}"
LOG_FILE="${LOG_FILE:-$SPESA_DIR/boot_cron_report.log}"
WAIT_SECONDS="${WAIT_SECONDS:-30}"
AUTO_RESTART_CROND="${AUTO_RESTART_CROND:-1}"
MAX_LOG_KB="${MAX_LOG_KB:-256}"
ROTATE_KEEP="${ROTATE_KEEP:-3}"

rotate_log_if_needed() {
  [ -f "$LOG_FILE" ] || return 0

  SIZE_BYTES=$(wc -c < "$LOG_FILE" 2>/dev/null)
  [ -n "$SIZE_BYTES" ] || return 0

  MAX_BYTES=$((MAX_LOG_KB * 1024))
  [ "$SIZE_BYTES" -lt "$MAX_BYTES" ] && return 0

  i=$ROTATE_KEEP
  while [ "$i" -ge 2 ]; do
    prev=$((i - 1))
    [ -f "${LOG_FILE}.${prev}" ] && mv "${LOG_FILE}.${prev}" "${LOG_FILE}.${i}"
    i=$prev
  done

  mv "$LOG_FILE" "${LOG_FILE}.1"
  : > "$LOG_FILE"
}

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S %Z') | $*" >> "$LOG_FILE"
}

mkdir -p "$SPESA_DIR" 2>/dev/null || true

touch "$LOG_FILE" 2>/dev/null || exit 1
rotate_log_if_needed

log "===== BOOT CRON GUARD START ====="
log "TERMUX_HOME=$TERMUX_HOME SPESA_DIR=$SPESA_DIR WAIT_SECONDS=$WAIT_SECONDS AUTO_RESTART_CROND=$AUTO_RESTART_CROND MAX_LOG_KB=$MAX_LOG_KB ROTATE_KEEP=$ROTATE_KEEP"

if command -v pgrep >/dev/null 2>&1; then
  pgrep -a -f "runsv|crond|svlogd" >> "$LOG_FILE" 2>&1 || log "No runsv/crond/svlogd processes found at start"
else
  ps -ef | grep -E "runsv|crond|svlogd" | grep -v grep >> "$LOG_FILE" 2>&1 || log "No runsv/crond/svlogd processes found at start"
fi

if command -v sv >/dev/null 2>&1; then
  sv status crond >> "$LOG_FILE" 2>&1 || log "sv status crond failed"
else
  log "sv command not found"
fi

log "Sleeping ${WAIT_SECONDS}s to allow post-boot service stabilization"
sleep "$WAIT_SECONDS"

is_crond_alive() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "[c]rond" >/dev/null 2>&1
  else
    ps -ef | grep -E "[c]rond" >/dev/null 2>&1
  fi
}

if is_crond_alive; then
  log "crond is alive after wait"
else
  log "crond is NOT alive after wait"

  if [ "$AUTO_RESTART_CROND" = "1" ]; then
    log "Trying: sv restart crond"
    if command -v sv >/dev/null 2>&1; then
      sv restart crond >> "$LOG_FILE" 2>&1 || log "sv restart crond failed"
      sleep 3
      if is_crond_alive; then
        log "crond recovered after restart"
      else
        log "crond still NOT alive after restart"
      fi
      sv status crond >> "$LOG_FILE" 2>&1 || true
    else
      log "Cannot restart: sv command not found"
    fi
  else
    log "AUTO_RESTART_CROND=0, restart skipped"
  fi
fi

if command -v pgrep >/dev/null 2>&1; then
  pgrep -a -f "runsv|crond|svlogd" >> "$LOG_FILE" 2>&1 || true
else
  ps -ef | grep -E "runsv|crond|svlogd" | grep -v grep >> "$LOG_FILE" 2>&1 || true
fi

log "===== BOOT CRON GUARD END ====="
