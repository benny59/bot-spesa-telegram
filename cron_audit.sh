#!/data/data/com.termux/files/usr/bin/sh

# Read-only cron diagnostic report for Termux production environment.
# It prints cron daemon status, heartbeat continuity, and check_spesa execution traces.

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
SPESA_DIR="${SPESA_DIR:-$TERMUX_HOME/spesa}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-$SPESA_DIR/cron_heartbeat.log}"
CHECK_SPESA_LOG="${CHECK_SPESA_LOG:-$SPESA_DIR/cron_check_spesa.log}"
CROND_LOG_DIR="${CROND_LOG_DIR:-/data/data/com.termux/files/usr/var/log/sv/crond}"
CROND_CURRENT_LOG="$CROND_LOG_DIR/current"
RUNIT_CROND_RUN="/data/data/com.termux/files/usr/var/service/crond/run"

CROND_ALIVE="no"

epoch_now() {
  date +%s 2>/dev/null
}

epoch_from_date() {
  date -d "$1" +%s 2>/dev/null
}

seconds_to_human() {
  SEC="$1"
  if [ -z "$SEC" ] || [ "$SEC" -lt 0 ] 2>/dev/null; then
    echo "unknown"
    return
  fi
  D=$((SEC / 86400))
  H=$(((SEC % 86400) / 3600))
  M=$(((SEC % 3600) / 60))
  S=$((SEC % 60))
  printf "%dd %02dh %02dm %02ds" "$D" "$H" "$M" "$S"
}

print_section() {
  printf "\n===== %s =====\n" "$1"
}

print_section "TIMESTAMP"
date "+%Y-%m-%d %H:%M:%S %Z"

print_section "PROCESS STATUS"
if command -v pgrep >/dev/null 2>&1; then
  pgrep -a -f "runsv crond|crond|svlogd" || true
  if pgrep -f "[c]rond" >/dev/null 2>&1; then
    CROND_ALIVE="yes"
  fi
else
  ps -ef | grep -E "runsv crond|crond|svlogd" | grep -v grep || true
  if ps -ef | grep -E "[c]rond" >/dev/null 2>&1; then
    CROND_ALIVE="yes"
  fi
fi

if command -v sv >/dev/null 2>&1; then
  print_section "RUNIT SERVICE STATUS"
  sv status crond 2>&1 || true
fi

print_section "RUNIT CROND RUN"
if [ -f "$RUNIT_CROND_RUN" ]; then
  sed -n '1,120p' "$RUNIT_CROND_RUN" 2>&1 || true
else
  echo "Service run file not found: $RUNIT_CROND_RUN"
fi

print_section "VERDICT"
if [ "$CROND_ALIVE" = "yes" ]; then
  echo "CROND_STATUS=ALIVE"
else
  echo "CROND_STATUS=DEAD"
fi

print_section "CRONTAB"
crontab -l 2>&1 || true

print_section "CROND LOG DIR"
if [ -d "$CROND_LOG_DIR" ]; then
  ls -lah "$CROND_LOG_DIR" 2>&1 || true
  if [ -f "$CROND_CURRENT_LOG" ]; then
    print_section "CROND CURRENT (tail 120)"
    tail -n 120 "$CROND_CURRENT_LOG" 2>&1 || true
  fi
else
  echo "Directory not found: $CROND_LOG_DIR"
fi

print_section "LAST-SEEN ANALYSIS"
NOW_EPOCH=$(epoch_now)

if [ -f "$HEARTBEAT_FILE" ]; then
  LAST_HEARTBEAT_LINE=$(tail -n 1 "$HEARTBEAT_FILE" 2>/dev/null)
  echo "Last heartbeat line: $LAST_HEARTBEAT_LINE"

  # Supports both: "Fri Jul 24 15:37:00 CEST 2026 ..." and "2026-07-24 15:37:00 ..."
  HEARTBEAT_TS=$(echo "$LAST_HEARTBEAT_LINE" | awk '{print $1" "$2" "$3" "$4" "$5" "$6}')
  HB_EPOCH=$(epoch_from_date "$HEARTBEAT_TS")
  if [ -z "$HB_EPOCH" ]; then
    HEARTBEAT_TS=$(echo "$LAST_HEARTBEAT_LINE" | awk '{print $1" "$2}')
    HB_EPOCH=$(epoch_from_date "$HEARTBEAT_TS")
  fi

  if [ -n "$HB_EPOCH" ] && [ -n "$NOW_EPOCH" ]; then
    AGE=$((NOW_EPOCH - HB_EPOCH))
    echo "Heartbeat age: $(seconds_to_human "$AGE")"
  else
    echo "Heartbeat age: unknown"
  fi
else
  echo "No heartbeat file: $HEARTBEAT_FILE"
fi

if [ -f "$CROND_CURRENT_LOG" ]; then
  LAST_CROND_LINE=$(tail -n 1 "$CROND_CURRENT_LOG" 2>/dev/null)
  echo "Last crond log line: $LAST_CROND_LINE"

  CROND_TS=$(echo "$LAST_CROND_LINE" | awk -F' ' '{print $1}' | tr '_' ' ')
  CROND_EPOCH=$(epoch_from_date "$CROND_TS")
  if [ -n "$CROND_EPOCH" ] && [ -n "$NOW_EPOCH" ]; then
    AGE=$((NOW_EPOCH - CROND_EPOCH))
    echo "Crond log age: $(seconds_to_human "$AGE")"
  else
    echo "Crond log age: unknown"
  fi
else
  echo "No crond current log: $CROND_CURRENT_LOG"
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

print_section "LOGCAT HINTS (crond/oom/kill)"
if command -v logcat >/dev/null 2>&1; then
  logcat -d -v time 2>/dev/null | grep -Ei "crond|runsv|lowmemorykiller|oom|killed process|termux" | tail -n 120 || true
else
  echo "logcat command not available"
fi

print_section "END"
