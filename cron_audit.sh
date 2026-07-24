#!/data/data/com.termux/files/usr/bin/sh

# Read-only cron diagnostic report for Termux production environment.
# It prints cron daemon status, heartbeat continuity, and check_spesa execution traces.

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
SPESA_DIR="${SPESA_DIR:-$TERMUX_HOME/spesa}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-$SPESA_DIR/cron_heartbeat.log}"
CHECK_SPESA_LOG="${CHECK_SPESA_LOG:-$SPESA_DIR/cron_check_spesa.log}"
CROND_LOG_DIR="${CROND_LOG_DIR:-/data/data/com.termux/files/usr/var/log/sv/crond}"

print_section() {
  printf "\n===== %s =====\n" "$1"
}

print_section "TIMESTAMP"
date "+%Y-%m-%d %H:%M:%S %Z"

print_section "PROCESS STATUS"
if command -v pgrep >/dev/null 2>&1; then
  pgrep -a -f "runsv crond|crond|svlogd" || true
else
  ps -ef | grep -E "runsv crond|crond|svlogd" | grep -v grep || true
fi

if command -v sv >/dev/null 2>&1; then
  print_section "RUNIT SERVICE STATUS"
  sv status crond 2>&1 || true
fi

print_section "CRONTAB"
crontab -l 2>&1 || true

print_section "CROND LOG DIR"
if [ -d "$CROND_LOG_DIR" ]; then
  ls -lah "$CROND_LOG_DIR" 2>&1 || true
  if [ -f "$CROND_LOG_DIR/current" ]; then
    print_section "CROND CURRENT (tail 120)"
    tail -n 120 "$CROND_LOG_DIR/current" 2>&1 || true
  fi
else
  echo "Directory not found: $CROND_LOG_DIR"
fi

print_section "HEARTBEAT SUMMARY"
if [ -f "$HEARTBEAT_FILE" ]; then
  wc -l "$HEARTBEAT_FILE" 2>&1 || true
  echo "-- last 20 lines --"
  tail -n 20 "$HEARTBEAT_FILE" 2>&1 || true

  if command -v date >/dev/null 2>&1; then
    echo "-- gaps > 90s --"
    awk '
      {
        ts = $1 " " $2
        cmd = "date -d \"" ts "\" +%s"
        cmd | getline cur
        close(cmd)
        if (cur == "") {
          next
        }
        if (prev != "" && (cur - prev) > 90) {
          printf "GAP %ds between %s and %s\n", (cur - prev), prev_ts, ts
        }
        prev = cur
        prev_ts = ts
      }
    ' "$HEARTBEAT_FILE" 2>/dev/null || echo "Gap analysis unavailable (date -d not supported?)"
  fi
else
  echo "Heartbeat file not found: $HEARTBEAT_FILE"
fi

print_section "CHECK_SPESA SUMMARY"
if [ -f "$CHECK_SPESA_LOG" ]; then
  wc -l "$CHECK_SPESA_LOG" 2>&1 || true
  echo "-- last 80 lines --"
  tail -n 80 "$CHECK_SPESA_LOG" 2>&1 || true
  echo "-- recent error-like lines --"
  grep -Ei "errore|error|fail|fatal|not found|killed|oom|exception" "$CHECK_SPESA_LOG" | tail -n 40 2>&1 || true
else
  echo "check_spesa log not found: $CHECK_SPESA_LOG"
fi

print_section "END"
