#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APK_DIR="$ROOT_DIR/apk"
VERSION_FILE="$APK_DIR/version.properties"
SIGNING_FILE="$APK_DIR/signing.properties"
RELEASE_DIR="$APK_DIR/releases"

if [ ! -f "$SIGNING_FILE" ]; then
  echo "Firma non configurata. Esegui prima: scripts/init_android_signing.sh" >&2
  exit 1
fi

VERSION_NAME=$(sed -n 's/^VERSION_NAME=//p' "$VERSION_FILE")
VERSION_CODE=$(sed -n 's/^VERSION_CODE=//p' "$VERSION_FILE")
if [ -z "$VERSION_NAME" ] || [ -z "$VERSION_CODE" ]; then
  echo "Versione Android non valida in $VERSION_FILE" >&2
  exit 1
fi

cd "$APK_DIR"
./gradlew :app:assembleRelease

SOURCE_APK="$APK_DIR/app/build/outputs/apk/release/app-release.apk"
TARGET_APK="$RELEASE_DIR/BotSpesa-v${VERSION_NAME}.apk"
mkdir -p "$RELEASE_DIR"
cp "$SOURCE_APK" "$TARGET_APK"

echo "APK release: $TARGET_APK"
echo "Versione: $VERSION_NAME (code $VERSION_CODE)"
sha256sum "$TARGET_APK"
