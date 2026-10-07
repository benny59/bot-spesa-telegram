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

CERT_FILE="$BOT_DIR/certs/fullchain.pem"
HEALTH_LOG="$BOT_DIR/health_check.log"
CERT_WARN_DAYS="${CERT_WARN_DAYS:-14}"
HEALTH_MAX_LOG_KB="${HEALTH_MAX_LOG_KB:-256}"

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

rotate_health_log_if_needed() {
    [ -f "$HEALTH_LOG" ] || return 0
    SIZE_BYTES=$(wc -c < "$HEALTH_LOG" 2>/dev/null)
    [ -n "$SIZE_BYTES" ] || return 0
    [ "$SIZE_BYTES" -lt $((HEALTH_MAX_LOG_KB * 1024)) ] && return 0
    mv "$HEALTH_LOG" "${HEALTH_LOG}.1" 2>/dev/null || true
    : > "$HEALTH_LOG"
}

# Verifica end-to-end la catena DuckDNS -> Tailscale -> certificato -> api_server,
# chiamando /ping sul nome pubblico esattamente come farebbe l'app Android da remoto.
check_https_health() {
    if [ ! -f "$CERT_FILE" ]; then
        [ "$ACTION" = "health" ] && echo "[check_spesa][health] HTTPS non configurato (nessun certificato in $CERT_FILE)"
        return 0
    fi
    OPENSSL_BIN=$(command -v openssl 2>/dev/null)
    CURL_BIN=$(command -v curl 2>/dev/null)
    [ -n "$OPENSSL_BIN" ] && [ -n "$CURL_BIN" ] || return 0

    DOMAIN=$("$OPENSSL_BIN" x509 -in "$CERT_FILE" -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^,]*' | head -1 | cut -d: -f2)
    [ -n "$DOMAIN" ] || DOMAIN="(sconosciuto)"

    ENDDATE=$("$OPENSSL_BIN" x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
    END_EPOCH=$(date -d "$ENDDATE" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    if [ -n "$END_EPOCH" ]; then
        DAYS_LEFT=$(( (END_EPOCH - NOW_EPOCH) / 86400 ))
    else
        DAYS_LEFT="?"
    fi

    # /ping richiede il Bearer token (prima filter di api_server.rb): lo leggiamo
    # dallo stesso spesa.db usato dall'app, così il check valida anche l'auth.
    API_TOKEN=""
    if [ -n "$RUBY_BIN" ] && [ -f "$BOT_DIR/spesa.db" ]; then
        API_TOKEN=$("$RUBY_BIN" -e '
          require "sqlite3"
          db = SQLite3::Database.new(ARGV[0])
          row = db.execute("SELECT value FROM config WHERE key = ?", ["api_token"]).first
          print row ? row[0] : ""
        ' "$BOT_DIR/spesa.db" 2>/dev/null)
    fi

    ERR_FILE=$(mktemp 2>/dev/null || echo "/tmp/check_spesa_health_err.$$")
    if [ -n "$API_TOKEN" ]; then
        HTTP_CODE=$("$CURL_BIN" -sS --max-time 5 -H "Authorization: Bearer $API_TOKEN" -o /dev/null -w '%{http_code}' "https://$DOMAIN:$HTTPS_PORT/ping" 2>"$ERR_FILE")
    else
        HTTP_CODE=$("$CURL_BIN" -sS --max-time 5 -o /dev/null -w '%{http_code}' "https://$DOMAIN:$HTTPS_PORT/ping" 2>"$ERR_FILE")
    fi
    CURL_RC=$?
    CURL_ERR=$(cat "$ERR_FILE" 2>/dev/null)
    rm -f "$ERR_FILE" 2>/dev/null

    STATUS="OK"
    REASON=""
    if [ "$CURL_RC" -ne 0 ] || { [ "$HTTP_CODE" != "200" ] && [ -n "$API_TOKEN" ]; }; then
        STATUS="FAIL"
        case "$CURL_RC" in
            6) REASON="DNS non risolve $DOMAIN (DuckDNS giu o record non aggiornato)" ;;
            7) REASON="connessione rifiutata/non raggiungibile (Tailscale giu?)" ;;
            28) REASON="timeout di connessione (Tailscale giu?)" ;;
            35|60) REASON="problema certificato TLS" ;;
            0) REASON="HTTP $HTTP_CODE inatteso da api_server (token letto ma rifiutato?)" ;;
            *) REASON="curl rc=$CURL_RC: $CURL_ERR" ;;
        esac
    elif [ "$HTTP_CODE" = "401" ]; then
        # Token non recuperabile da spesa.db, ma la risposta 401 conferma comunque
        # che DNS, Tailscale e certificato TLS funzionano fino all'app.
        STATUS="WARN"
        REASON="token api non recuperato da spesa.db: connettivita' verificata ma auth non testata"
    elif [ "$HTTP_CODE" != "200" ]; then
        STATUS="FAIL"
        REASON="HTTP $HTTP_CODE inatteso da api_server"
    elif [ "$DAYS_LEFT" != "?" ] && [ "$DAYS_LEFT" -le "$CERT_WARN_DAYS" ]; then
        STATUS="WARN"
        REASON="certificato in scadenza tra $DAYS_LEFT giorni"
    fi

    rotate_health_log_if_needed
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$STATUS] dominio=$DOMAIN scadenza_cert=${DAYS_LEFT}gg http=$HTTP_CODE ${REASON:+motivo=\"$REASON\"}" >> "$HEALTH_LOG"

    if [ "$ACTION" = "health" ]; then
        echo "[check_spesa][health] stato=$STATUS dominio=$DOMAIN scadenza_cert=${DAYS_LEFT}gg http=$HTTP_CODE ${REASON:+($REASON)}"
    fi
}

if [ "$ACTION" = "health" ]; then
    check_https_health
    exit 0
fi

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
    check_https_health
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
check_https_health
