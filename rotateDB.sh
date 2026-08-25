#!/usr/bin/env bash
set -eu

DB_DIR="${DB_DIR:-$(pwd)}"
DB_FILE="${DB_FILE:-$DB_DIR/spesa.db}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

if [ ! -f "$DB_FILE" ]; then
  echo "DB non trovato: $DB_FILE" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
TARGET="$DB_DIR/spesa_${STAMP}.db"
cp "$DB_FILE" "$TARGET"

find "$DB_DIR" -maxdepth 1 -type f -name 'spesa_*.db' ! -name "spesa_${STAMP}.db" -mtime +"$RETENTION_DAYS" -delete

echo "Backup creato: $TARGET"
echo "Retention: $RETENTION_DAYS giorni"
