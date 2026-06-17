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
            DelayControls(delay: vm.delay)

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

    /// La piste de balayage. On n'utilise `TimelineView(.animation)` (redessin à chaque image)
    /// QUE quand le métronome tourne ; à l'arrêt, rendu statique (zéro redessin inutile).
    private var sweep: some View {
        GeometryReader { geo in
            if metronome.isRunning {
                TimelineView(.animation) { context in
                    bar(width: geo.size.width, phase: metronome.phase(at: context.date), running: true)
                }
            } else {
                bar(width: geo.size.width, phase: 0, running: false)
            }
        }
    }

    /// Dessine la piste + le repère + la barre pour une phase donnée (0…1).
    private func bar(width w: CGFloat, phase: Double, running: Bool) -> some View {
        // Barre : droite (phase→0) vers gauche (phase→1). Battement quand elle touche la gauche.
        let x = w * (1 - phase)
        // Le repère « brille » quand on approche du battement (fin de course à gauche).
        let nearBeat = running ? max(0, (phase - 0.85) / 0.15) : 0

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))

            // Repère de battement (bord gauche).
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 4)
                .opacity(0.4 + 0.6 * nearBeat)

            // La barre qui balaie.
            Rectangle()
                .fill(Color.primary.opacity(running ? 0.9 : 0.25))
                .frame(width: 4)
                .offset(x: x - 2)
        }
    }
}
