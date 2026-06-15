import CoreAudio
import Foundation

/// Représentation d'un périphérique audio Core Audio.
///
/// Core Audio identifie chaque périphérique (carte son, casque, BlackHole, ampli BT…)
/// par un `AudioDeviceID` (un simple entier). On enrichit ça avec le nom lisible,
/// l'UID stable (utile pour retrouver un périph. entre deux lancements) et le nombre
/// de canaux en entrée / sortie pour savoir si on peut l'utiliser comme source ou destination.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let inputChannels: Int
    let outputChannels: Int

    /// Un périphérique peut servir d'ENTRÉE s'il expose au moins un canal d'entrée.
    var hasInput: Bool { inputChannels > 0 }
    /// … et de SORTIE s'il expose au moins un canal de sortie.
    var hasOutput: Bool { outputChannels > 0 }
}
