#!/data/data/com.termux/files/usr/bin/sh
# wifi_watchdog.sh - riporta online il telefono quando Android non si riconnette al Wi-Fi.
#
# Contesto: dopo il riavvio notturno (05:00) il segnale può scendere sotto la soglia
# di Android ("Networks filtered out due to low signal strength") e, con lo schermo
# spento, il telefono resta offline finché qualcuno non accende lo schermo.
# Questo script simula quel gesto (WAKEUP) e, se non basta, fa un ciclo del Wi-Fi.
#
# Uso da cron (ogni 5 minuti):
#   */5 * * * * /data/data/com.termux/files/usr/bin/sh /data/data/com.termux/files/home/spesa/wifi_watchdog.sh
#
# Prova a mano (senza agire): sh wifi_watchdog.sh --dry-run
# Prova a mano (forza l'azione): sh wifi_watchdog.sh --force
#
# Richiede root (su -c) per input keyevent e svc wifi.

export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin:$PATH"

BOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOG_FILE="${WIFI_WATCHDOG_LOG:-$BOT_DIR/wifi_watchdog.log}"
STATE_FILE="${WIFI_WATCHDOG_STATE:-$BOT_DIR/.wifi_watchdog.state}"
LOCK_DIR="${WIFI_WATCHDOG_LOCK:-$BOT_DIR/.wifi_watchdog.lock}"
TEST_URL="${WIFI_WATCHDOG_URL:-https://api.telegram.org}"
FAILS_BEFORE_WAKE="${WIFI_WATCHDOG_FAILS_WAKE:-2}"      # 2 cicli (~10 min) -> sveglia schermo
FAILS_BEFORE_CYCLE="${WIFI_WATCHDOG_FAILS_CYCLE:-3}"    # 3 cicli (~15 min) -> spegne/riaccende Wi-Fi
LOG_MAX_KB="${WIFI_WATCHDOG_LOG_MAX_KB:-256}"

MODE="${1:-}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

# Evita esecuzioni sovrapposte (mkdir è atomico). Lock vecchio di >10 min = residuo.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null
        mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM

# Rotazione minima del log
if [ -f "$LOG_FILE" ]; then
    SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null)
    if [ -n "$SIZE" ] && [ "$SIZE" -gt $((LOG_MAX_KB * 1024)) ]; then
        mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
    fi
fi

# Qualsiasi risposta HTTP (anche 4xx) prova che DNS + rete + TLS funzionano.
# Fallisce solo se curl non riesce a connettersi (rc != 0).
online() {
    curl -sS --max-time 8 -o /dev/null -I "$TEST_URL" 2>/dev/null
}

run_root() {
    if [ "$MODE" = "--dry-run" ]; then
        log "[dry-run] su -c '$*'"
        return 0
    fi
    su -c "$*" >/dev/null 2>&1
}

FAILS=0
[ -f "$STATE_FILE" ] && FAILS=$(cat "$STATE_FILE" 2>/dev/null)
case "$FAILS" in ''|*[!0-9]*) FAILS=0 ;; esac

if [ "$MODE" != "--force" ] && online; then
    if [ "$FAILS" -gt 0 ]; then
        log "rete tornata online dopo $FAILS controlli falliti"
    fi
    echo 0 > "$STATE_FILE"
    exit 0
fi

FAILS=$((FAILS + 1))
echo "$FAILS" > "$STATE_FILE"
[ "$MODE" = "--force" ] && FAILS=$FAILS_BEFORE_CYCLE
log "rete assente (controllo fallito n.$FAILS)"

if [ "$FAILS" -ge "$FAILS_BEFORE_WAKE" ]; then
    log "azione 1: sveglio lo schermo (KEYCODE_WAKEUP) e riabilito il Wi-Fi"
    run_root "input keyevent KEYCODE_WAKEUP"
    run_root "svc wifi enable"
    sleep 25
    if online; then
        log "OK dopo sveglia schermo"
        echo 0 > "$STATE_FILE"
        exit 0
    fi
fi

if [ "$FAILS" -ge "$FAILS_BEFORE_CYCLE" ]; then
    log "azione 2: ciclo Wi-Fi (disable/enable) con schermo acceso"
    run_root "input keyevent KEYCODE_WAKEUP"
    run_root "svc wifi disable"
    sleep 4
    run_root "svc wifi enable"
    sleep 30
    if online; then
        log "OK dopo ciclo Wi-Fi"
        echo 0 > "$STATE_FILE"
        exit 0
    fi
    log "ancora offline dopo il ciclo Wi-Fi (segnale troppo debole?)"
fi
exit 0
