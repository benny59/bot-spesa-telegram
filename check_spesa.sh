#!/data/data/com.termux/files/usr/bin/sh

# Ambiente minimale di cron: forza PATH Termux + Android
export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin:$PATH"

# Rileva la cartella dove si trova lo script
REALPATH_BIN=$(command -v realpath 2>/dev/null)
if [ -n "$REALPATH_BIN" ]; then
    BOT_DIR=$(dirname "$($REALPATH_BIN "$0")")
else
    BOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fi

PKILL_BIN=$(command -v pkill 2>/dev/null)
RUBY_BIN=$(command -v ruby 2>/dev/null)
WAKELOCK_BIN=$(command -v termux-wake-lock 2>/dev/null)

LOG_FILE="$BOT_DIR/bot_spesa.log"
PID_FILE="$BOT_DIR/bot_spesa.pid"
API_PID_FILE="$BOT_DIR/api_server.pid"
API_LOG_FILE="$BOT_DIR/api_server.log"

# Possibili argomenti: nessuno, oppure "restart" per forzare la chiusura dei processi attuali prima del riavvio.
ACTION="${1:-}"

print_pid_snapshot() {
    label="${1:-prima}"
    BOT_PID="$(cat "$PID_FILE" 2>/dev/null || echo "")"
    API_PID="$(cat "$API_PID_FILE" 2>/dev/null || echo "")"
    echo "[check_spesa] PID ${label}: bot=${BOT_PID:-none} api=${API_PID:-none}"
}

list_matching_pids() {
    ps -eo pid,args 2>/dev/null | grep -E "$1" | grep -v grep | awk '{print $1}' | sort -u
}

kill_existing_processes() {
    BOT_PIDS=$(list_matching_pids "ruby .*bot_spesa\.rb|bot_spesa\.rb")
    API_PIDS=$(list_matching_pids "ruby .*api_server\.rb|puma .*4568|puma .*\[spesa\]")

    if [ -n "$BOT_PIDS" ]; then
        echo "$BOT_PIDS" | while IFS= read -r pid; do
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        done
    fi

    if [ -n "$API_PIDS" ]; then
        echo "$API_PIDS" | while IFS= read -r pid; do
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        done
    fi

    sleep 1

    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
    [ -f "$API_PID_FILE" ] && rm -f "$API_PID_FILE"
}

# Verifica che il PID sia vivo E sia realmente il bot Ruby atteso.
is_bot_running() {
    [ -f "$PID_FILE" ] || return 1

    PID=$(cat "$PID_FILE" 2>/dev/null)
    case "$PID" in
        ''|*[!0-9]*) return 1 ;;
    esac

    kill -0 "$PID" 2>/dev/null || return 1

    if [ -r "/proc/$PID/cmdline" ]; then
        CMDLINE=$(tr '\000' ' ' < "/proc/$PID/cmdline")
        echo "$CMDLINE" | grep -q "bot_spesa.rb" || return 1
    fi

    return 0
}

is_api_running() {
    [ -f "$API_PID_FILE" ] || return 1

    PID=$(cat "$API_PID_FILE" 2>/dev/null)
    case "$PID" in
        ''|*[!0-9]*) return 1 ;;
    esac

    kill -0 "$PID" 2>/dev/null || return 1

    if [ -r "/proc/$PID/cmdline" ]; then
        CMDLINE=$(tr '\000' ' ' < "/proc/$PID/cmdline")
        echo "$CMDLINE" | grep -q "api_server.rb" || return 1
    fi

    return 0
}

if [ "$ACTION" = "restart" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - restart richiesto: chiusura processi esistenti..." >> "$LOG_FILE"
    print_pid_snapshot "prima"
    kill_existing_processes
fi

# 1. Controlla se il processo è realmente vivo usando il PID salvato
if is_bot_running; then
    : # bot attivo, continua a controllare api_server
else
    # Il bot è morto o il PID è stantio
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Bot non attivo, pulizia e riavvio..." >> $LOG_FILE
    
    # Pulizia radicale per evitare il Conflict 409
    [ -n "$PKILL_BIN" ] && "$PKILL_BIN" -f "ruby.*bot_spesa.rb"
    [ -f "$PID_FILE" ] && rm "$PID_FILE"
    
    [ -n "$WAKELOCK_BIN" ] && "$WAKELOCK_BIN"
    cd "$BOT_DIR"
    if [ -n "$RUBY_BIN" ]; then
        nohup "$RUBY_BIN" bot_spesa.rb >> "$LOG_FILE" 2>&1 < /dev/null &
        echo $! > "$PID_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERRORE: ruby non trovato nel PATH" >> "$LOG_FILE"
        exit 1
    fi
fi

# --- Controlla e riavvia il daemon HTTP api_server ---
if is_api_running; then
    print_pid_snapshot "dopo"
    exit 0
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - api_server non attivo, riavvio..." >> "$API_LOG_FILE"
[ -f "$API_PID_FILE" ] && rm "$API_PID_FILE"
[ -n "$WAKELOCK_BIN" ] && "$WAKELOCK_BIN"
cd "$BOT_DIR"
BUNDLE_BIN=$(command -v bundle 2>/dev/null)
if [ -n "$BUNDLE_BIN" ]; then
    nohup "$BUNDLE_BIN" exec "$RUBY_BIN" api_server.rb >> "$API_LOG_FILE" 2>&1 < /dev/null &
    echo $! > "$API_PID_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERRORE: bundle non trovato nel PATH" >> "$API_LOG_FILE"
fi

echo "[check_spesa] PID dopo: bot=$(cat "$PID_FILE" 2>/dev/null || echo none) api=$(cat "$API_PID_FILE" 2>/dev/null || echo none)"
