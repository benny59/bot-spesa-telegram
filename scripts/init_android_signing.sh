#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SIGNING_FILE="$ROOT_DIR/apk/signing.properties"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bot-spesa-telegram"
KEYSTORE_FILE="$CONFIG_DIR/android-release.jks"

if [ -e "$SIGNING_FILE" ] || [ -e "$KEYSTORE_FILE" ]; then
  echo "Firma Android gia inizializzata."
  echo "Configurazione: $SIGNING_FILE"
  echo "Keystore: $KEYSTORE_FILE"
  exit 0
fi

command -v keytool >/dev/null 2>&1 || {
  echo "Errore: keytool non trovato. Installa un JDK 17 o successivo." >&2
  exit 1
}
command -v openssl >/dev/null 2>&1 || {
  echo "Errore: openssl non trovato." >&2
  exit 1
}

umask 077
mkdir -p "$CONFIG_DIR"
PASSWORD=$(openssl rand -hex 24)

keytool -genkeypair \
  -keystore "$KEYSTORE_FILE" \
  -storetype JKS \
  -storepass "$PASSWORD" \
  -keypass "$PASSWORD" \
  -alias bot-spesa \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "CN=Bot Spesa, OU=Private Distribution, O=Bot Spesa, C=IT"

cat > "$SIGNING_FILE" <<EOF
storeFile=$KEYSTORE_FILE
storePassword=$PASSWORD
keyAlias=bot-spesa
keyPassword=$PASSWORD
EOF

chmod 600 "$SIGNING_FILE" "$KEYSTORE_FILE"
echo "Firma Android inizializzata. Esegui subito un backup di:"
echo "  $SIGNING_FILE"
echo "  $KEYSTORE_FILE"
