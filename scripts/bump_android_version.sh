#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Uso: $0 VERSIONE (esempio: $0 1.2.0)" >&2
  exit 1
fi

VERSION_NAME=$1
case "$VERSION_NAME" in
  *[!0-9.]*|.*|*.|*..*)
    echo "Versione non valida: $VERSION_NAME" >&2
    exit 1
    ;;
esac

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION_FILE="$ROOT_DIR/apk/version.properties"
CURRENT_CODE=$(sed -n 's/^VERSION_CODE=//p' "$VERSION_FILE")

case "$CURRENT_CODE" in
  ''|*[!0-9]*)
    echo "VERSION_CODE non valido in $VERSION_FILE" >&2
    exit 1
    ;;
esac

NEXT_CODE=$((CURRENT_CODE + 1))
cat > "$VERSION_FILE" <<EOF
VERSION_CODE=$NEXT_CODE
VERSION_NAME=$VERSION_NAME
EOF

echo "Versione Android aggiornata: $VERSION_NAME (code $NEXT_CODE)"
