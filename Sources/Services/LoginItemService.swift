import Foundation
import ServiceManagement

/// Gère le **lancement automatique au démarrage** de la session (login item).
///
/// Utilise `SMAppService.mainApp` (macOS 13+) : l'API moderne qui enregistre l'app elle-même
/// comme élément d'ouverture. `register()` active, `unregister()` désactive ; `status` indique
/// l'état réel (le système peut exiger une approbation manuelle dans Réglages › Éléments d'ouverture).
@MainActor
final class LoginItemService: ObservableObject {

    /// Vrai si le lancement au démarrage est actif.
    @Published private(set) var isEnabled = false
    /// Vrai si le système attend une approbation manuelle de l'utilisateur.
    @Published private(set) var needsApproval = false

    init() { refresh() }

    /// Relit l'état courant auprès du système.
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true; needsApproval = false
        case .requiresApproval:
            isEnabled = false; needsApproval = true
        default:                      // .notRegistered, .notFound…
            isEnabled = false; needsApproval = false
        }
    }

    /// Active ou désactive le lancement au démarrage.
    func setEnabled(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem error: \(error.localizedDescription)")
        }
        refresh()
    }
}
