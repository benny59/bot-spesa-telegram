#!/usr/bin/env bash
# setup_android.sh - Setup ambiente Android e build APK
# Esegui dalla cartella apk/: bash setup_android.sh
set -e

ANDROID_SDK_ROOT="$HOME/Android/Sdk"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-15859902_latest.zip"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP"
SDK_PLATFORM="platforms;android-34"
SDK_BUILDTOOLS="build-tools;34.0.0"

step() { echo; echo "==> $1"; }

# --- 1. Java ---
step "Verifica Java 17+"
java -version 2>&1 | grep -q "17\|21\|22\|23\|24" || {
  echo "ERRORE: Java 17+ richiesto. Installa con: sudo apt install openjdk-17-jdk"
  exit 1
}
echo "OK: $(java -version 2>&1 | head -1)"

# --- 2. Gradle ---
step "Verifica/installa Gradle"
if ! command -v gradle &>/dev/null; then
  echo "Gradle non trovato. Installo via snap..."
  sudo snap install gradle --classic
else
  echo "OK: $(gradle -version 2>&1 | grep Gradle)"
fi

# --- 3. Android SDK cmdline-tools ---
step "Verifica Android SDK"
if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]; then
  echo "Android SDK non trovato. Scarico cmdline-tools..."
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

  TMP=$(mktemp -d)
  echo "  Download da Google (181 MB)..."
  wget -q --show-progress -O "$TMP/$CMDLINE_TOOLS_ZIP" "$CMDLINE_TOOLS_URL"
  echo "  Estrazione..."
  unzip -q "$TMP/$CMDLINE_TOOLS_ZIP" -d "$TMP/"
  mv "$TMP/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -rf "$TMP"
  echo "OK: cmdline-tools installati"
else
  echo "OK: cmdline-tools già presenti"
fi

# --- 4. Variabili d'ambiente ---
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

# Aggiungi a .bashrc se non già presente
grep -q "ANDROID_HOME" "$HOME/.bashrc" 2>/dev/null || {
  echo "" >> "$HOME/.bashrc"
  echo "# Android SDK" >> "$HOME/.bashrc"
  echo "export ANDROID_HOME=\"$ANDROID_SDK_ROOT\"" >> "$HOME/.bashrc"
  echo "export PATH=\"\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools\"" >> "$HOME/.bashrc"
  echo "OK: variabili aggiunte a ~/.bashrc"
}

# --- 5. SDK platform e build-tools ---
step "Installa Android SDK platform 34 e build-tools"
if [ ! -d "$ANDROID_SDK_ROOT/platforms/android-34" ]; then
  echo "Accetto le licenze e installo componenti SDK (ci vuole qualche minuto)..."
  yes | sdkmanager --licenses > /dev/null 2>&1 || true
  sdkmanager "$SDK_PLATFORM" "$SDK_BUILDTOOLS"
  echo "OK: SDK installato"
else
  echo "OK: SDK platform 34 già presente"
fi

# --- 6. local.properties ---
step "Crea local.properties"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat > "$SCRIPT_DIR/local.properties" << EOF
sdk.dir=$ANDROID_SDK_ROOT
EOF
echo "OK: local.properties creato"

# --- 7. Gradle wrapper ---
step "Genera Gradle wrapper"
cd "$SCRIPT_DIR"
if [ ! -f "gradle/wrapper/gradle-wrapper.jar" ]; then
  gradle wrapper --gradle-version=8.6
  echo "OK: wrapper generato"
else
  echo "OK: wrapper già presente"
fi

# --- 8. Build APK debug ---
step "Build APK debug"
./gradlew assembleDebug

APK_PATH="$SCRIPT_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK_PATH" ]; then
  echo
  echo "======================================================"
  echo "  APK pronto: $APK_PATH"
  echo "  Installa con: adb install -r $APK_PATH"
  echo "======================================================"
else
  echo "ERRORE: APK non trovato dopo il build"
  exit 1
fi
