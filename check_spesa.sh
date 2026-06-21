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

# 1. Controlla se il processo è realmente vivo usando il PID salvato
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    # Il bot è vivo e vegeto
    # echo "$(date '+%Y-%m-%d %H:%M:%S') - Bot attivo (PID: $(cat $PID_FILE))" >> $LOG_FILE
    exit 0
else
    # Il bot è morto o il PID è stantio
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Bot non attivo, pulizia e riavvio..." >> $LOG_FILE
    
    # Pulizia radicale per evitare il Conflict 409
    [ -n "$PKILL_BIN" ] && "$PKILL_BIN" -f "ruby.*bot_spesa.rb"
    [ -f "$PID_FILE" ] && rm "$PID_FILE"
    
    [ -n "$WAKELOCK_BIN" ] && "$WAKELOCK_BIN"
    cd "$BOT_DIR"
    if [ -n "$RUBY_BIN" ]; then
        "$RUBY_BIN" bot_spesa.rb >> "$LOG_FILE" 2>&1 &
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERRORE: ruby non trovato nel PATH" >> "$LOG_FILE"
        exit 1
    fi
fi
