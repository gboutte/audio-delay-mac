import SwiftUI

/// Point d'entrée de l'app.
///
/// `vm` et `metronome` sont créés ICI (au niveau de l'`App`), pas dans `ContentView` : ainsi le
/// moteur audio **survit à la fermeture de la fenêtre** et reste piloté par l'icône de la barre
/// de menus. L'app ne se termine pas tant que l'icône de menu (`MenuBarExtra`) est présente.
@main
struct AudioDelayApp: App {
    @StateObject private var vm = AudioDelayViewModel()
    @StateObject private var metronome = MetronomeController()

    var body: some Scene {
        // Fenêtre principale (unique, ré-ouvrable depuis le menu).
        Window("Audio Delay", id: "main") {
            ContentView(vm: vm, metronome: metronome)
        }
        .windowResizability(.contentSize)

        // Icône permanente dans la barre de menus (en haut à droite).
        MenuBarExtra {
            MenuBarContent(vm: vm)
        } label: {
            Image(systemName: vm.isRunning ? "speaker.wave.2.circle.fill" : "speaker.wave.2.circle")
        }
        .menuBarExtraStyle(.window)   // panneau riche (slider, boutons) plutôt qu'un simple menu
    }
}
