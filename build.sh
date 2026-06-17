#!/bin/bash
#
# Compile l'app SwiftUI en un bundle .app, sans Xcode complet (Command Line Tools suffisent).
#
# Étapes :
#   1. swiftc compile tous les .swift de Sources/ en un binaire.
#   2. On monte la structure de bundle macOS (.app/Contents/MacOS + Info.plist).
#   3. Signature ad-hoc (nécessaire pour que macOS attribue une identité stable à l'app,
#      utile pour l'autorisation micro/TCC).
#
set -euo pipefail

APP_NAME="AudioDelay"
BUNDLE_ID="com.local.audiodelay"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

echo "==> Nettoyage"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

echo "==> Compilation Swift"
# -parse-as-library : indispensable pour qu'un @main struct App soit le point d'entrée.
# -target ...macosx13.0 : plancher de déploiement raisonnable (on build sur macOS 26).
SOURCES=$(find "$ROOT/Sources" -name '*.swift')
# shellcheck disable=SC2086
swiftc \
  -parse-as-library \
  -O \
  -target x86_64-apple-macosx13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreAudio \
  $SOURCES \
  -o "$MACOS_DIR/$APP_NAME"

echo "==> Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>Délai audio</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <!-- Agent app : pas d'icône dans le Dock, vit uniquement dans la barre de menus. -->
    <key>LSUIElement</key>             <true/>
    <!-- Texte affiché lors de la demande d'autorisation micro (obligatoire pour capturer l'audio). -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Cette app capture le son système (via BlackHole) pour lui appliquer un délai avant de le renvoyer vers votre sortie audio.</string>
</dict>
</plist>
PLIST

echo "==> Signature ad-hoc"
codesign --force --sign - "$APP_DIR"

echo ""
echo "✅ Build terminé : $APP_DIR"
echo "   Lancer avec :  open \"$APP_DIR\""
