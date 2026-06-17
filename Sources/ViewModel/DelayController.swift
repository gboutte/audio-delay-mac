import Foundation

/// État du délai, ISOLÉ dans son propre `ObservableObject`.
///
/// Pourquoi séparé du `AudioDelayViewModel` : le slider fait varier la valeur ~60 fois/seconde.
/// Si elle était publiée sur le `vm`, toute la fenêtre (Pickers compris) se redessinerait à chaque
/// cran. Ici, seules les vues qui observent CE contrôleur (le bloc `DelayControls`) se redessinent.
@MainActor
final class DelayController: ObservableObject {

    private static let key = "audioDelay.delayMs"
    private let engine: DelayAudioEngine
    private var persistWork: DispatchWorkItem?

    /// Délai en ms. `didSet` applique en direct au moteur et persiste (de façon débouncée).
    @Published var ms: Double {
        didSet {
            engine.delayMilliseconds = ms
            schedulePersist()
        }
    }

    init(engine: DelayAudioEngine) {
        self.engine = engine
        self.ms = UserDefaults.standard.double(forKey: Self.key)   // didSet ne se déclenche pas en init
    }

    /// Applique la valeur courante au moteur (à appeler au démarrage de la lecture).
    func applyToEngine() {
        engine.delayMilliseconds = ms
    }

    /// Réglage fin ±delta, borné à 0…1000 ms.
    func nudge(by deltaMs: Double) {
        ms = min(1000, max(0, (ms + deltaMs).rounded()))
    }

    /// Écrit la valeur dans `UserDefaults` après une courte inactivité (évite ~60 écritures/s
    /// pendant le glissement du slider).
    private func schedulePersist() {
        persistWork?.cancel()
        let value = ms
        let work = DispatchWorkItem { UserDefaults.standard.set(value, forKey: Self.key) }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
