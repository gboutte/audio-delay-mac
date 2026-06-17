#!/bin/bash
#
# Compile l'app puis l'installe dans /Applications.
#
# Pourquoi installer là : le "lancement au démarrage" (login item) pointe vers l'emplacement
# du bundle. Depuis /Applications, l'emplacement est stable ; depuis build/ il serait recréé
# à chaque compilation.
#
set -euo pipefail

APP_NAME="AudioDelay"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

echo "==> Compilation"
"$ROOT/build.sh"

echo "==> Installation dans /Applications"
# Si l'app tourne, on la quitte pour pouvoir la remplacer.
killall "$APP_NAME" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo ""
echo "✅ Installé : $DEST"
echo "   Lancer avec :  open \"$DEST\""
echo "   (Le démarrage automatique s'active depuis l'icône de la barre de menus : « Launch at login ».)"
