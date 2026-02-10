#!/data/data/com.termux/files/usr/bin/sh

# Rileva la cartella dove si trova lo script
BOT_DIR=$(dirname "$(realpath "$0")")
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
    pkill -f "ruby.*bot_spesa.rb"
    [ -f "$PID_FILE" ] && rm "$PID_FILE"
    
    termux-wake-lock
    cd "$BOT_DIR"
    ruby bot_spesa.rb >> "$LOG_FILE" 2>&1 &
fi
