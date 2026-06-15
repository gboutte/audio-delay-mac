import CoreAudio
import Foundation

/// Abstraction de la SOURCE audio à retarder — le point de découplage clé du projet.
///
/// L'idée : quelle que soit la méthode de capture (BlackHole aujourd'hui, Core Audio
/// process tap demain), tout se ramène à *« fournir un `AudioDeviceID` à brancher en
/// entrée de l'`AVAudioEngine` »*.
///
/// - BlackHole : la source EST un vrai périphérique HAL → on renvoie directement son ID.
/// - Process tap (futur) : on créera un *aggregate device* enveloppant un tap sur le son
///   système, puis on renverra l'ID de cet aggregate. `deactivate()` détruira le tap.
///
/// Changer de méthode = écrire une nouvelle implémentation de ce protocole. Le reste du
/// code (engine, délai, UI) ne bouge pas.
protocol AudioCaptureProvider {
    /// Nom lisible (pour l'UI / les logs).
    var displayName: String { get }

    /// Prépare la capture et renvoie l'`AudioDeviceID` à utiliser comme entrée de l'engine.
    /// Peut lever une erreur si la source n'est pas disponible.
    func activate() throws -> AudioDeviceID

    /// Libère les ressources éventuellement créées par `activate()` (tap, aggregate…).
    /// No-op pour une source qui est déjà un périphérique réel.
    func deactivate()
}

/// Implémentation actuelle : la source est un périphérique d'entrée réel choisi par
/// l'utilisateur (typiquement « BlackHole 2ch », mais ça marche pour n'importe quelle entrée).
///
/// `activate()` se contente de renvoyer l'ID — aucune ressource à créer ni à libérer.
struct DeviceInputCaptureProvider: AudioCaptureProvider {
    let device: AudioDevice

    var displayName: String { device.name }

    func activate() throws -> AudioDeviceID {
        device.id
    }

    func deactivate() {
        // Rien à faire : on n'a pas créé de ressource Core Audio.
    }
}

// MARK: - Jalon pour l'étape 2 (laissé volontairement en commentaire)
//
// Future implémentation, sans rien changer d'autre dans l'app :
//
// final class ProcessTapCaptureProvider: AudioCaptureProvider {
//     var displayName: String { "Son système (process tap)" }
//     private var tapID: AudioObjectID = 0
//     private var aggregateID: AudioDeviceID = 0
//
//     func activate() throws -> AudioDeviceID {
//         // 1) CATapDescription + AudioHardwareCreateProcessTap(...)
//         // 2) Créer un aggregate device qui inclut le tap
//         // 3) return aggregateID
//     }
//     func deactivate() {
//         // AudioHardwareDestroyAggregateDevice(aggregateID)
//         // AudioHardwareDestroyProcessTap(tapID)
//     }
// }
