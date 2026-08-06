#!/usr/bin/env bash
# setup_build.sh - Installa l'ambiente di build Android e compila il debug APK
# Esegui: bash setup_build.sh
set -e

ANDROID_SDK_DIR="$HOME/Android/Sdk"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
CMDLINE_ZIP="/tmp/cmdline-tools.zip"
GRADLE_VERSION="8.6"

echo "=== 1/5  Verifica Java ==="
java -version 2>&1 | head -1
echo ""

# ---- SDKMAN + Gradle --------------------------------------------------------
echo "=== 2/5  Installazione Gradle $GRADLE_VERSION via SDKMAN ==="
if [ ! -d "$HOME/.sdkman" ]; then
  curl -s "https://get.sdkman.io" | bash
fi
# shellcheck disable=SC1090
source "$HOME/.sdkman/bin/sdkman-init.sh"
if ! sdk list gradle 2>/dev/null | grep -q "* $GRADLE_VERSION"; then
  sdk install gradle "$GRADLE_VERSION"
fi
sdk use gradle "$GRADLE_VERSION"
gradle -v | head -1
echo ""

# ---- Android cmdline-tools --------------------------------------------------
echo "=== 3/5  Installazione Android SDK cmdline-tools ==="
mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
if [ ! -d "$ANDROID_SDK_DIR/cmdline-tools/latest/bin" ]; then
  echo "Download cmdline-tools..."
  curl -L "$CMDLINE_TOOLS_URL" -o "$CMDLINE_ZIP"
  unzip -q "$CMDLINE_ZIP" -d "$ANDROID_SDK_DIR/cmdline-tools"
  mv "$ANDROID_SDK_DIR/cmdline-tools/cmdline-tools" "$ANDROID_SDK_DIR/cmdline-tools/latest"
  rm "$CMDLINE_ZIP"
  echo "cmdline-tools installati."
else
  echo "cmdline-tools già presenti."
fi

export ANDROID_HOME="$ANDROID_SDK_DIR"
export PATH="$PATH:$ANDROID_SDK_DIR/cmdline-tools/latest/bin:$ANDROID_SDK_DIR/platform-tools"
echo ""

# ---- SDK components ---------------------------------------------------------
echo "=== 4/5  Installazione piattaforma e build-tools ==="
yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
echo ""

# ---- Gradle wrapper + build -------------------------------------------------
echo "=== 5/5  Generazione wrapper e build APK ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Genera il wrapper JAR (richiede Gradle installato)
gradle wrapper --gradle-version="$GRADLE_VERSION"

# Aggiunge ANDROID_HOME al local.properties
echo "sdk.dir=$ANDROID_SDK_DIR" > local.properties

./gradlew assembleDebug

APK_PATH="$SCRIPT_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK_PATH" ]; then
  echo ""
  echo "✅ APK pronto: $APK_PATH"
  echo "   Installa con: adb install $APK_PATH"
else
  echo "❌ Build completata ma APK non trovato in $APK_PATH"
fi
