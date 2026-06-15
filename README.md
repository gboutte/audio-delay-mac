# Délai audio (macOS)

Petite app SwiftUI native qui capture le son système, lui applique un **délai réglable**
(0–1000 ms, ajustable en direct) et le renvoie vers le périphérique de sortie de ton choix
(ex. ampli Bluetooth). Sert à **resynchroniser le son sur l'image** quand on caste l'écran
vers un projecteur (image en retard) avec le son en Bluetooth (en avance).

## Architecture

Le son système est dirigé vers **BlackHole** (carte son virtuelle). L'app capture BlackHole,
retarde le flux, et le ressort vers la sortie réelle (HP du Mac, ampli BT…).

```
[apps macOS] → Sortie système = BlackHole 2ch
                        │  (BlackHole recopie sa sortie vers son entrée)
                        ▼
        ┌──────────── Aggregate device privé ────────────┐
        │   sous-périph. 0 : sortie réelle (canaux 0,1)   │
        │   sous-périph. 1 : BlackHole (entrée 2ch)       │   horloge maître = BlackHole
        └─────────────────────────────────────────────────┘   drift correction sur la sortie
                        │
                        ▼
        AudioUnit HAL full-duplex (kAudioUnitSubType_HALOutput)
          render callback :  entrée BlackHole → ligne à retard (ring buffer) → sortie réelle
                             (carte de canaux [0,1,-1,-1] : on n'écrit QUE sur la sortie réelle)
```

### Pourquoi cette architecture (et pas `AVAudioEngine`)

Deux verrous macOS rencontrés et levés :

1. **Un seul `AVAudioEngine` ne peut pas lier entrée et sortie à deux périphériques
   différents** (entrée=BlackHole, sortie=HP) — il renvoie l'erreur `-10851`. Solution : on
   regroupe les deux dans **un seul périphérique agrégé** (aggregate device), à horloge unique.
2. **`AVAudioEngine` se lie de force au périphérique par défaut du système** (le
   « CADefaultDeviceAggregate ») et **ignore** tout `kAudioOutputUnitProperty_CurrentDevice`
   qu'on tente de lui imposer. Solution : on descend d'un cran et on pilote **directement une
   AudioUnit HAL**, qui, elle, respecte le périphérique demandé.

Avantage bonus : entrée et sortie partageant l'horloge de l'agrégat, le **délai** se réduit à
un simple décalage lecture/écriture dans un buffer circulaire — pas de dérive, pas de
conversion de fréquence. La *drift correction* de l'agrégat absorbe la dérive d'horloge d'un
ampli Bluetooth.

### Fichiers

- `Sources/Models/AudioDevice.swift` — modèle d'un périphérique Core Audio.
- `Sources/Services/AudioDeviceService.swift` — énumération des périphériques (HAL).
- `Sources/Services/AggregateDeviceService.swift` — création/destruction de l'**aggregate
  device** privé { sortie réelle + BlackHole }.
- `Sources/Services/AudioCaptureProvider.swift` — abstraction swappable de la capture
  (BlackHole aujourd'hui, process tap envisageable plus tard).
- `Sources/Services/DelayAudioEngine.swift` — **AudioUnit HAL** + render callback + ligne à
  retard (le cœur temps réel).
- `Sources/ViewModel/AudioDelayViewModel.swift` — pont UI ↔ services.
- `Sources/Views/ContentView.swift` + `Sources/App/AudioDelayApp.swift` — UI SwiftUI.

## Prérequis

- macOS 13+ (développé/testé sur macOS 26, Mac Intel x86_64).
- **Command Line Tools** (`xcode-select --install`) — Xcode complet pas nécessaire.
- **BlackHole 2ch** installé (voir ci-dessous).

## 1. Activer BlackHole (capture du son système)

```bash
brew install blackhole-2ch    # ou : brew reinstall blackhole-2ch
```

> L'installeur demande le mot de passe admin et redémarre `coreaudiod`. **Un redémarrage du
> Mac peut être nécessaire** pour que le driver soit chargé. Vérifie ensuite :
> ```bash
> system_profiler SPAudioDataType | grep -i blackhole   # doit afficher "BlackHole 2ch"
> ```

## 2. Compiler

```bash
./build.sh
```

Le script compile tous les `.swift` de `Sources/` avec `swiftc`, monte le bundle
`build/AudioDelay.app` (Info.plist inclus) et le signe en *ad-hoc*.

## 3. Lancer

```bash
open build/AudioDelay.app
```

Au premier **Start**, macOS demande l'autorisation **Microphone** : accepte (la capture audio
passe par cette autorisation, même si la source est BlackHole et non un vrai micro). Si tu l'as
refusée : *Réglages › Confidentialité et sécurité › Microphone*.

> **Pour voir les logs** au lancement, exécute le binaire directement :
> ```bash
> build/AudioDelay.app/Contents/MacOS/AudioDelay
> ```
> Note : après un rebuild, relance bien l'app (`killall AudioDelay` puis `open …`) — un simple
> `open` sur une app déjà ouverte ne recharge pas le nouveau binaire.

## 4. Router le son et calibrer

1. **Diriger le son système vers BlackHole** : *Réglages › Son › Sortie* → **BlackHole 2ch**.
   (Le Mac ne joue alors plus le son sur ses HP : c'est normal, le son ressort via l'app.)
2. Dans l'app :
   - **Entrée** = `BlackHole 2ch` (présélectionné si détecté).
   - **Sortie** = ta sortie réelle : HP du Mac pour tester, ou ton ampli Bluetooth (clique
     **Rafraîchir** après l'avoir connecté).
3. **Start**. Lance ta vidéo/musique. À 0 ms, le son sort immédiatement (passe-plat).
4. Monte le **délai** progressivement (slider, puis ±1 / ±10 ms) jusqu'à ce que le son colle
   à l'image. Le réglage s'applique **en direct**.

### Astuce de calibration
Pars d'une vidéo avec un gros plan parlant. Augmente le délai par paliers de 10 ms jusqu'à
dépasser légèrement, puis affine au ±1 ms. Note la valeur qui marche pour ta config.

## Limites connues / pistes

- Le délai max est fixé à **1000 ms** (buffer circulaire de 2 s).
- La capture repose sur BlackHole ; une migration vers le **Core Audio process tap**
  (macOS 14.4+) permettrait de capturer le son système sans driver tiers — l'abstraction
  `AudioCaptureProvider` est là pour faciliter ce changement.
