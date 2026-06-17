import SwiftUI

/// Interface principale : sélecteurs entrée/sortie, curseur de délai, Start/Stop.
struct ContentView: View {
    @ObservedObject var vm: AudioDelayViewModel
    @ObservedObject var metronome: MetronomeController
    @State private var showMetronome = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            devicePickers

            inputMeter

            Divider()

            DelayControls(vm: vm)

            Divider()

            footer
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 460)
        .onAppear { vm.refreshDevices() }
        .sheet(isPresented: $showMetronome) {
            MetronomeView(metronome: metronome, vm: vm)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Délai audio").font(.title2).bold()
                Text(vm.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showMetronome = true
            } label: {
                Label("Métronome", systemImage: "metronome")
            }
            .help("Métronome de calibration : aligne le flash (image projetée) avec le clic (audio retardé).")

            Button {
                vm.refreshDevices()
            } label: {
                Label("Rafraîchir", systemImage: "arrow.clockwise")
            }
            .help("Recharger la liste des périphériques (ex. après avoir branché l'ampli BT).")
        }
    }

    /// VU-mètre du son capturé sur l'entrée — confirme visuellement que BlackHole reçoit du son.
    /// Le `TimelineView` ne tourne QUE pendant la lecture et ne redessine QUE ce petit mètre
    /// (il lit `vm.inputLevel` à la demande, sans `@Published` → pas de re-render global).
    private var inputMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Niveau d'entrée")
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    if vm.isRunning {
                        TimelineView(.periodic(from: Date(), by: 1.0 / 30.0)) { _ in
                            // sqrt : booste visuellement les niveaux faibles (échelle perceptuelle).
                            let level = min(1.0, Double(max(0, vm.inputLevel)).squareRoot())
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(level > 0.9 ? Color.red : Color.green)
                                    .frame(width: geo.size.width * CGFloat(level))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .frame(height: 10)
        }
    }

    private var devicePickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ENTRÉE : la source du son à retarder (idéalement BlackHole).
            Picker("Entrée (source)", selection: $vm.selectedInputID) {
                ForEach(vm.inputDevices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .disabled(vm.isRunning)

            // SORTIE : vers l'ampli Bluetooth.
            Picker("Sortie (ampli BT)", selection: $vm.selectedOutputID) {
                ForEach(vm.outputDevices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .disabled(vm.isRunning)

            if vm.inputDevices.first(where: { $0.name.localizedCaseInsensitiveContains("blackhole") }) == nil {
                Label("BlackHole non détecté en entrée — voir le README pour l'activer.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = vm.errorMessage {
                Label(error, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                vm.toggle()
            } label: {
                Label(vm.isRunning ? "Stop" : "Start",
                      systemImage: vm.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(vm.isRunning ? .red : .accentColor)
        }
    }
}
