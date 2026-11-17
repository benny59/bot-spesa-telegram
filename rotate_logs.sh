#!/data/data/com.termux/files/usr/bin/sh
# rotate_logs.sh - rotazione "copytruncate" dei log del progetto (nessun riavvio necessario).
#
# I processi scrivono in append (>>), quindi si copia il file in .1.gz e lo si azzera sul posto.
# Tiene KEEP generazioni compresse (.1.gz, .2.gz, ...).
#
# Uso da cron (una volta a settimana, domenica 03:30):
#   30 3 * * 0 /data/data/com.termux/files/usr/bin/sh /data/data/com.termux/files/home/spesa/rotate_logs.sh >> /data/data/com.termux/files/home/spesa/rotate_logs.log 2>&1
#
# Prova a secco: sh rotate_logs.sh --dry-run

export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:$PATH"

BOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KEEP="${ROTATE_KEEP:-3}"
MAX_KB="${ROTATE_MAX_KB:-2048}"           # ruota se > 2 MB
PRE_DB_DAYS="${ROTATE_PRE_DB_DAYS:-30}"   # snapshot pre_*.db più vecchi di N giorni (0 = non toccare)
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"; }

rotate() {
    f="$1"
    [ -f "$f" ] || return 0
    size=$(wc -c < "$f" 2>/dev/null)
    [ -n "$size" ] || return 0
    [ "$size" -gt $((MAX_KB * 1024)) ] || return 0

    say "ruoto $(basename "$f") ($((size / 1024)) KB)"
    [ "$DRY" -eq 1 ] && return 0

    i=$KEEP
    while [ "$i" -gt 1 ]; do
        prev=$((i - 1))
        [ -f "$f.$prev.gz" ] && mv -f "$f.$prev.gz" "$f.$i.gz"
        i=$prev
    done
    # copytruncate: se la compressione fallisce NON si azzera l'originale
    if gzip -c "$f" > "$f.1.gz.tmp" 2>/dev/null; then
        mv -f "$f.1.gz.tmp" "$f.1.gz"
        : > "$f"
    else
        rm -f "$f.1.gz.tmp"
        say "ERRORE compressione $(basename "$f"): lascio il file intatto"
    fi
}

for name in api_server.log bot_spesa.log cron_check_spesa.log cron_heartbeat.log \
            cron_daily_comment.log cronoscopetta.log wifi_watchdog.log; do
    rotate "$BOT_DIR/$name"
done

# Il log di rotateDB e RSS finisce in rssGenerator/cron.log (vedi crontab): stessa regola
[ -d "$HOME/rssGenerator" ] && rotate "$HOME/rssGenerator/cron.log"

# Snapshot manuali pre_*.db (rotateDB.sh gestisce solo spesa_*.db)
if [ "$PRE_DB_DAYS" -gt 0 ]; then
    old=$(find "$BOT_DIR" -maxdepth 1 -type f -name 'pre_*.db' -mtime +"$PRE_DB_DAYS" 2>/dev/null)
    if [ -n "$old" ]; then
        echo "$old" | while IFS= read -r p; do
            say "snapshot vecchio: $(basename "$p")"
            [ "$DRY" -eq 1 ] || rm -f "$p"
        done
    fi
fi
say "rotazione completata${DRY:+ }$([ "$DRY" -eq 1 ] && echo '(dry-run)')"
