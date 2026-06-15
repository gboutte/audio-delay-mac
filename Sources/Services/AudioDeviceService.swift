import CoreAudio
import Foundation

/// Service d'énumération des périphériques audio via le HAL (Hardware Abstraction Layer)
/// de Core Audio.
///
/// Notions Core Audio utiles :
/// - `kAudioObjectSystemObject` est l'objet racine ; on l'interroge pour lister les périphériques.
/// - On lit les "propriétés" d'un objet audio avec `AudioObjectGetPropertyData`, en décrivant
///   QUELLE propriété via une `AudioObjectPropertyAddress` (selector + scope + element).
/// - L'API est en C : on passe presque tout par pointeur (`&variable`) et on récupère un
///   `OSStatus` (`noErr` == succès).
enum AudioDeviceService {

    // MARK: - API publique

    /// Tous les périphériques connus du système, transformés en `AudioDevice`.
    static func allDevices() -> [AudioDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        // 1) Combien d'octets fait la liste des IDs ? (on demande la taille avant de lire)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        // 2) On lit réellement les IDs dans un tableau dimensionné.
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }

        // 3) On enrichit chaque ID en modèle complet (nom, canaux…).
        return ids.compactMap { device(for: $0) }
    }

    /// Construit un `AudioDevice` complet à partir d'un ID.
    static func device(for id: AudioDeviceID) -> AudioDevice? {
        guard let name = stringProperty(id, selector: kAudioObjectPropertyName) else { return nil }
        let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID) ?? ""
        let inputs = channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let outputs = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        return AudioDevice(id: id, name: name, uid: uid,
                           inputChannels: inputs, outputChannels: outputs)
    }

    /// ID du périphérique d'entrée par défaut (pour présélectionner intelligemment).
    static func defaultInputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    /// ID du périphérique de sortie par défaut.
    static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    // MARK: - Lecture de propriétés bas niveau

    /// Lit une propriété de type chaîne (nom, UID…). Core Audio renvoie un `CFString`
    /// "retenu" qu'il faut libérer côté Swift via `takeRetainedValue()`.
    private static func stringProperty(_ id: AudioObjectID,
                                       selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfString: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &cfString) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value = cfString?.takeRetainedValue() else { return nil }
        return value as String
    }

    /// Compte les canaux d'un périphérique pour un "scope" donné (entrée OU sortie).
    ///
    /// La config de flux (`kAudioDevicePropertyStreamConfiguration`) est renvoyée sous forme
    /// d'un `AudioBufferList` : une liste de buffers, chacun annonçant son nombre de canaux.
    /// On somme les canaux de tous les buffers. C'est ce qui permet de savoir si un périph.
    /// sait capturer (scope input) et/ou jouer (scope output).
    private static func channelCount(_ id: AudioObjectID,
                                     scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return 0 }

        // L'AudioBufferList a une taille variable : on alloue de la mémoire brute.
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }

        let listPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, listPtr) == noErr else {
            return 0
        }

        // `UnsafeMutableAudioBufferListPointer` itère proprement sur les buffers.
        let buffers = UnsafeMutableAudioBufferListPointer(listPtr)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }
}
