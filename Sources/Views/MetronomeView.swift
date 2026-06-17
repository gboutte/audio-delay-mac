import SwiftUI

/// Fenêtre de calibration : une **barre balaie de droite à gauche** ; le **clic** sonore tombe
/// quand elle atteint le **repère de gauche**. On voit donc le battement arriver (prévisible).
///
/// Usage : on aligne le clic *entendu* (audio retardé par l'app) avec la barre touchant le repère
/// *vu* sur le projecteur (image retardée par le cast), en ajustant le délai.
struct MetronomeView: View {
    @ObservedObject var metronome: MetronomeController
    @ObservedObject var vm: AudioDelayViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Calibration metronome").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }

            sweep
                .frame(height: 90)

            // Réglage du tempo.
            VStack(spacing: 6) {
                HStack {
                    Text("Tempo")
                    Spacer()
                    Text("\(Int(metronome.bpm)) BPM")
                        .font(.system(.body, design: .monospaced)).bold()
                }
                Slider(value: $metronome.bpm, in: 30...180, step: 1)
            }

            Button {
                metronome.toggle()
            } label: {
                Label(metronome.isRunning ? "Stop metronome" : "Start metronome",
                      systemImage: metronome.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(metronome.isRunning ? .red : .accentColor)

            Divider()

            // Réglage du délai EN DIRECT, ici même, pour caler sans fermer le métronome.
            DelayControls(vm: vm)

            if !vm.isRunning {
                Label("Playback isn't started (Start): the click won't come back out.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Adjust the delay above until the click you hear lands exactly when the bar "
                 + "reaches the marker, on the projector.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 380)
        .onDisappear { metronome.stop() }
    }

    /// La piste de balayage. `TimelineView(.animation)` redessine à chaque image ; la position se
    /// déduit du temps → mouvement fluide et régulier, insensible au jitter du thread principal.
    private var sweep: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let w = geo.size.width
                let phase = metronome.phase(at: context.date)
                // Barre : droite (phase→0) vers gauche (phase→1). Battement quand elle touche la gauche.
                let x = w * (1 - phase)
                // Le repère « brille » quand on approche du battement (fin de course à gauche).
                let nearBeat = metronome.isRunning ? max(0, (phase - 0.85) / 0.15) : 0

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))

                    // Repère de battement (bord gauche).
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 4)
                        .opacity(0.4 + 0.6 * nearBeat)

                    // La barre qui balaie.
                    Rectangle()
                        .fill(Color.primary.opacity(metronome.isRunning ? 0.9 : 0.25))
                        .frame(width: 4)
                        .offset(x: x - 2)
                }
            }
        }
    }
}
