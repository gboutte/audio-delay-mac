import CoreAudio
import Foundation

/// Erreurs liées à la création du périphérique agrégé.
enum AggregateDeviceError: LocalizedError {
    case creationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let status):
            return "Could not create the aggregate device (status \(status))."
        }
    }
}

/// Crée à la volée un **périphérique agrégé** (aggregate device) Core Audio regroupant
/// la sortie réelle (HP du Mac, ampli BT…) ET BlackHole, pour contourner LA limitation
/// d'`AVAudioEngine` sur macOS : un seul engine ne peut pas lier entrée et sortie à deux
/// périphériques *différents*.
///
/// Idée : aux yeux de l'engine il n'y a plus qu'UN device (l'agrégat). L'entrée lit les
/// canaux de BlackHole (le son du bureau), la sortie écrit sur les canaux de la sortie réelle.
///
/// Notions Core Audio :
/// - Un aggregate device se décrit par un dictionnaire (`CFDictionary`) listant ses
///   « sous-périphériques » par leur UID, et `AudioHardwareCreateAggregateDevice` renvoie
///   l'ID du device créé.
/// - L'ORDRE des sous-périphériques fixe l'ordre des canaux. On met la **sortie réelle en
///   premier** → ses canaux sont les indices 0,1 → c'est là que l'engine enverra le son.
///   BlackHole en second → ses canaux de sortie (2,3) restent inutilisés (pas de larsen).
/// - Le **master d'horloge** = BlackHole (horloge stable, calée sur le système). La sortie
///   réelle est « esclave » avec *drift compensation* activée → quand ce sera l'ampli BT,
///   Core Audio resamplera pour absorber la dérive d'horloge Bluetooth.
/// - `IsPrivate = 1` : l'agrégat n'est visible que par notre process et disparaît à la fin
///   (rien ne pollue les Réglages Son de l'utilisateur).
final class AggregateDeviceService {

    /// ID de l'agrégat courant (0 si aucun).
    private(set) var aggregateID: AudioDeviceID = 0

    /// UID stable de notre agrégat (réutilisé entre deux créations).
    private let aggregateUID = "com.local.audiodelay.aggregate"

    /// Crée l'agrégat { `outputUID` (sortie réelle), `inputUID` (BlackHole) } et renvoie son ID.
    /// - Parameters:
    ///   - outputUID: UID du périphérique de sortie réel (placé en premier → canaux 0,1).
    ///   - inputUID: UID de la source de capture (BlackHole) — aussi master d'horloge.
    func create(outputUID: String, inputUID: String) throws -> AudioDeviceID {
        // Détruire un éventuel agrégat précédent resté en place.
        destroy()

        let subDevices: [[String: Any]] = [
            // Sortie réelle EN PREMIER (canaux 0,1) + esclave horloge → drift compensation.
            [kAudioSubDeviceUIDKey as String: outputUID,
             kAudioSubDeviceDriftCompensationKey as String: 1],
            // BlackHole ensuite (ses canaux d'entrée alimentent l'engine).
            [kAudioSubDeviceUIDKey as String: inputUID],
        ]

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "AudioDelay Aggregate",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceMasterSubDeviceKey as String: inputUID,
            kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
        ]

        var id: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr, id != 0 else {
            throw AggregateDeviceError.creationFailed(status)
        }
        aggregateID = id
        return id
    }

    /// Détruit l'agrégat courant (no-op s'il n'y en a pas).
    func destroy() {
        guard aggregateID != 0 else { return }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        aggregateID = 0
    }
}
