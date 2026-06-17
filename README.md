# Audio Delay (macOS)

A small native SwiftUI app that captures system audio, applies an **adjustable delay**
(0–1000 ms, live), and sends it back to the output device of your choice (e.g. a Bluetooth amp).
Use it to **re-sync audio to video** when mirroring your screen to a projector (delayed image)
while the sound plays over Bluetooth (early).

It runs as a **menu bar app** (no Dock icon): the audio engine keeps running even when the window
is closed, and you control it from the menu bar icon.

## Architecture

System audio is routed into **BlackHole** (a virtual sound card). The app captures BlackHole,
delays the stream, and sends it to the real output (Mac speakers, BT amp…).

```
[macOS apps] → System output = BlackHole 2ch
                        │  (BlackHole loops its output back to its input)
                        ▼
        ┌──────────── Private aggregate device ───────────┐
        │   sub-device 0 : real output (channels 0,1)      │
        │   sub-device 1 : BlackHole (2ch input)           │   clock master = BlackHole
        └──────────────────────────────────────────────────┘   drift correction on the output
                        │
                        ▼
        Full-duplex HAL AudioUnit (kAudioUnitSubType_HALOutput)
          render callback:  BlackHole input → delay line (ring buffer) → real output
                            (channel map [0,1,-1,-1]: write ONLY to the real output channels)
```

### Why this architecture (and not `AVAudioEngine`)

Two macOS roadblocks were hit and worked around:

1. **A single `AVAudioEngine` can't bind input and output to two different devices**
   (input = BlackHole, output = speakers) — it returns error `-10851`. Fix: combine both into a
   single **aggregate device** with one clock.
2. **`AVAudioEngine` force-binds to the system default device** (the "CADefaultDeviceAggregate")
   and **ignores** any `kAudioOutputUnitProperty_CurrentDevice` you set. Fix: drop down a level and
   drive a **HAL AudioUnit directly**, which does honor the requested device.

Bonus: since input and output share the aggregate's clock, the **delay** is just a read/write
offset in a circular buffer — no drift, no sample-rate conversion. The aggregate's drift
correction absorbs a Bluetooth amp's clock drift.

### Files

- `Sources/Models/AudioDevice.swift` — model of a Core Audio device.
- `Sources/Services/AudioDeviceService.swift` — device enumeration (HAL).
- `Sources/Services/AggregateDeviceService.swift` — creates/destroys the private **aggregate
  device** { real output + BlackHole }.
- `Sources/Services/AudioCaptureProvider.swift` — swappable capture abstraction (BlackHole today,
  process tap conceivable later).
- `Sources/Services/DelayAudioEngine.swift` — the real-time core: **HAL AudioUnit** + render
  callback + delay line.
- `Sources/Services/MetronomeController.swift` — calibration metronome (visual sweep + audible click).
- `Sources/ViewModel/AudioDelayViewModel.swift` — UI ↔ services bridge.
- `Sources/Views/` — SwiftUI views (`ContentView`, `DelayControls`, `MetronomeView`,
  `MenuBarContent`).
- `Sources/App/AudioDelayApp.swift` — app entry point (main window + menu bar item).

## Requirements

- macOS 13+ (developed/tested on macOS 26, Intel x86_64 Mac).
- **Command Line Tools** (`xcode-select --install`) — full Xcode not required.
- **BlackHole 2ch** installed (see below).

## 1. Enable BlackHole (system audio capture)

```bash
brew install blackhole-2ch    # or: brew reinstall blackhole-2ch
```

> The installer asks for your admin password and restarts `coreaudiod`. **A reboot may be
> required** for the driver to load. Then verify:
> ```bash
> system_profiler SPAudioDataType | grep -i blackhole   # should show "BlackHole 2ch"
> ```

## 2. Build

```bash
./build.sh
```

The script compiles every `.swift` in `Sources/` with `swiftc`, assembles the
`build/AudioDelay.app` bundle (with Info.plist) and signs it ad-hoc.

## 3. Run

```bash
open build/AudioDelay.app
```

This is a **menu bar app** (`LSUIElement`): there is **no Dock icon**. Look for the speaker icon
in the menu bar (top right). Click it, then **"Open window"** to access the full UI (device
selection, metronome…). On the first **Start**, macOS asks for **Microphone** permission: allow it
(audio capture goes through this permission, even though the source is BlackHole, not a real mic).
If you denied it: *Settings › Privacy & Security › Microphone*.

> **To see logs**, run the binary directly:
> ```bash
> build/AudioDelay.app/Contents/MacOS/AudioDelay
> ```
> Note: after a rebuild, relaunch the app (`killall AudioDelay` then `open …`) — a plain `open`
> on an already-running app does not reload the new binary.

## 4. Route the audio and calibrate

1. **Send system audio to BlackHole**: *Settings › Sound › Output* → **BlackHole 2ch**.
   (The Mac stops playing on its speakers — that's expected; the sound comes back out through the app.)
2. In the app window:
   - **Input** = `BlackHole 2ch` (preselected if detected).
   - **Output** = your real output: Mac speakers to test, or your Bluetooth amp (click **Refresh**
     after connecting it).
3. **Start**. Play your video/music. At 0 ms the sound comes out immediately (pass-through).
4. Increase the **delay** gradually (slider, then ±1 / ±10 ms) until the sound matches the image.
   The change applies **live**.

### Calibration metronome
Open **Metronome** from the window (or from the menu bar). A bar sweeps right→left and a **click**
fires when it reaches the left marker. The click travels through the delay; the sweep is shown on
screen (so delayed on the projector via screen mirroring). Adjust the delay — right there in the
metronome window — until the click you hear lands exactly when the bar reaches the marker on the
projector.

### Input level meter
The "Input level" bar confirms BlackHole is actually receiving sound while playing.

## Known limits / ideas

- Max delay is capped at **1000 ms** (2 s circular buffer).
- Capture relies on BlackHole; moving to the **Core Audio process tap** (macOS 14.4+) would capture
  system audio without a third-party driver — the `AudioCaptureProvider` abstraction is there to
  ease that change.

> Note: code comments are in French (learning notes); UI and this README are in English.
