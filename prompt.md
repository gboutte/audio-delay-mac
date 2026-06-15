# Prompt de reprise — après reboot

> Copie-colle le bloc ci-dessous dans Claude Code, à la racine du projet `audio-mixer-mac`.

---

On reprend le projet **app macOS de délai audio** (`audio-mixer-mac`). Le contexte complet est
dans ta mémoire de projet (`project-state.md`) ; résumé : app SwiftUI qui capture le son système
via **BlackHole**, applique un délai réglable (`AVAudioUnitDelay`) et le ressort vers mon ampli
Bluetooth, pour resynchroniser son/image lors d'un cast écran→projecteur. Le code est écrit et
compile (`./build.sh` → `build/AudioDelay.app`). Je viens de **redémarrer** après l'install de
BlackHole.

Fais dans l'ordre :

1. **Vérifie que BlackHole est actif** :
   `system_profiler SPAudioDataType | grep -i blackhole` (doit afficher "BlackHole 2ch").
   S'il manque, aide-moi à diagnostiquer avant d'aller plus loin.
2. **(Re)compile et lance** : `./build.sh` puis `open build/AudioDelay.app`.
3. **Guide-moi pour le routage et le test** :
   - Réglages › Son › Sortie → BlackHole 2ch
   - Dans l'app : Entrée = BlackHole, Sortie = mon ampli BT (Rafraîchir après l'avoir connecté),
     Start (j'accepte la perm micro), puis je monte le délai jusqu'à la synchro.
4. Je te dirai ce que ça donne (son vers l'ampli ? délai audible ? erreur affichée ?) et on
   ajustera, ou on passera à l'**étape 2** (aggregate device / process tap) si dérive d'horloge.

Rappel : je suis CTO, expert TS/NestJS/Angular/PHP mais **débutant Swift/Core Audio** — explique
le spécifique audio.
