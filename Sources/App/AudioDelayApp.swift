import SwiftUI

/// Point d'entrée de l'app SwiftUI.
///
/// `@main` désigne le type qui démarre l'application. `App` est le protocole de cycle de vie
/// SwiftUI ; `WindowGroup` crée la fenêtre principale contenant `ContentView`.
@main
struct AudioDelayApp: App {
    var body: some Scene {
        WindowGroup("Délai audio") {
            ContentView()
        }
        // Fenêtre non redimensionnable à outrance : contenu compact.
        .windowResizability(.contentSize)
    }
}
