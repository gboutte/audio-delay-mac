import SwiftUI

/// Interface principale : sélecteurs entrée/sortie, curseur de délai, Start/Stop.
struct ContentView: View {
    @StateObject private var vm = AudioDelayViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            devicePickers

            Divider()

            delayControls

            Divider()

            footer
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 420)
        .onAppear { vm.refreshDevices() }
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
                vm.refreshDevices()
            } label: {
                Label("Rafraîchir", systemImage: "arrow.clockwise")
            }
            .help("Recharger la liste des périphériques (ex. après avoir branché l'ampli BT).")
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

    private var delayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Délai")
                Spacer()
                Text("\(Int(vm.delayMs)) ms")
                    .font(.system(.title3, design: .monospaced))
                    .bold()
            }

            // Slider continu 0–1000 ms (réglage grossier + en direct).
            Slider(value: $vm.delayMs, in: 0...1000, step: 1) {
                Text("Délai")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("1000")
            }

            // Réglage fin : ±1 ms et ±10 ms.
            HStack(spacing: 8) {
                nudgeButton("-10", -10)
                nudgeButton("-1", -1)
                Spacer()
                nudgeButton("+1", 1)
                nudgeButton("+10", 10)
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

    private func nudgeButton(_ label: String, _ delta: Double) -> some View {
        Button(label) { vm.nudgeDelay(by: delta) }
            .monospacedDigit()
    }
}
