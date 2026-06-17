import SwiftUI
import AppKit

/// Contenu du panneau déroulant de l'icône de barre de menus : contrôles rapides accessibles
/// même quand la fenêtre principale est fermée (le moteur, lui, continue de tourner).
struct MenuBarContent: View {
    @ObservedObject var vm: AudioDelayViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Delay").font(.headline)
            Text(vm.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

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

            Divider()

            // Réglage du délai directement depuis la barre de menus.
            DelayControls(vm: vm)

            Divider()

            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Open window", systemImage: "macwindow")
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
