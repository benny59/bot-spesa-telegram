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
FUSER_BIN=$(command -v fuser 2>/dev/null)

LOG_FILE="$BOT_DIR/bot_spesa.log"
PID_FILE="$BOT_DIR/bot_spesa.pid"
API_PID_FILE="$BOT_DIR/api_server.pid"
API_LOG_FILE="$BOT_DIR/api_server.log"
API_PORT=4568
HTTPS_PORT="${SPESA_HTTPS_PORT:-4443}"

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

# Funzione per liberare forzatamente le porte dell'API (HTTP app Android + HTTPS PWA)
free_api_ports() {
    if [ -n "$FUSER_BIN" ]; then
        # Uccide qualsiasi processo stia occupando le porte
        "$FUSER_BIN" -k "$API_PORT/tcp" "$HTTPS_PORT/tcp" 2>/dev/null || true
    fi
}

kill_api_processes() {
    API_PIDS=$(list_matching_pids "ruby .*api_server\.rb|puma .*$API_PORT|puma .*\[spesa\]")

    if [ -n "$API_PIDS" ]; then
        echo "$API_PIDS" | while IFS= read -r pid; do
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        done
    fi

    # Pulizia preventiva delle porte di rete
    free_api_ports

    sleep 1

    [ -f "$API_PID_FILE" ] && rm -f "$API_PID_FILE"
}

kill_existing_processes() {
    BOT_PIDS=$(list_matching_pids "ruby .*bot_spesa\.rb|bot_spesa\.rb")

    if [ -n "$BOT_PIDS" ]; then
        echo "$BOT_PIDS" | while IFS= read -r pid; do
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        done
    fi

    kill_api_processes

    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
}

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
        # Puma rinomina il processo in "puma X.Y.Z (tcp://...) [spesa]"
        echo "$CMDLINE" | grep -qE "api_server\.rb|puma " || return 1
    fi
    return 0
}

if [ "$ACTION" = "restart" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - restart richiesto: chiusura processi esistenti..." >> "$LOG_FILE"
    print_pid_snapshot "prima"
    kill_existing_processes
elif [ "$ACTION" = "restart-api" ]; then
    # Usato dal rinnovo del certificato HTTPS (acme.sh --reloadcmd): il bot resta attivo
    echo "$(date '+%Y-%m-%d %H:%M:%S') - restart-api richiesto: chiusura api_server..." >> "$API_LOG_FILE"
    kill_api_processes
fi

# 1. Controllo Bot
if is_bot_running; then
    : 
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Bot non attivo, pulizia e riavvio..." >> "$LOG_FILE"
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

# 2. Controllo API Server
if is_api_running; then
    print_pid_snapshot "dopo"
    exit 0
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - api_server non attivo, riavvio..." >> "$API_LOG_FILE"

# *** AGGIUNTA CHIAVE ***: Libera le porte dell'API prima di riavviare,
# così da evitare errori "Address already in use" se il PID file era saltato ma Puma era ancora attivo.
free_api_ports

[ -f "$API_PID_FILE" ] && rm -f "$API_PID_FILE"
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
