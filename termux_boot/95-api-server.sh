#!/data/data/com.termux/files/usr/bin/sh

# Avvia il daemon HTTP api_server.rb per l'app Android.

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
SPESA_DIR="${SPESA_DIR:-$TERMUX_HOME/spesa}"
LOG="$SPESA_DIR/api_server.log"
PIDFILE="$SPESA_DIR/api_server.pid"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  exit 0
fi

cd "$SPESA_DIR"
nohup bundle exec ruby api_server.rb >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"
