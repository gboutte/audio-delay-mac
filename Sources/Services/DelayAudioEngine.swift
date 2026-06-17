import AVFoundation
import CoreAudio

/// Erreurs métier de la chaîne audio, avec un message lisible pour l'UI.
enum DelayEngineError: LocalizedError {
    case componentUnavailable
    case couldNotSetProperty(name: String, status: OSStatus)
    case initFailed(status: OSStatus)
    case startFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .componentUnavailable:
            return "AudioUnit HAL introuvable sur ce système."
        case .couldNotSetProperty(let name, let status):
            return "Échec de configuration « \(name) » (status \(status))."
        case .initFailed(let status):
            return "Initialisation de l'AudioUnit impossible (status \(status))."
        case .startFailed(let status):
            return "Démarrage de l'AudioUnit impossible (status \(status))."
        }
    }
}

/// Cœur audio : capture → délai → sortie, via une **AudioUnit HAL** pilotée à la main.
///
/// Pourquoi pas `AVAudioEngine` ? Parce qu'il se lie de force au périphérique PAR DÉFAUT du
/// système (le « CADefaultDeviceAggregate ») et ignore tout périphérique explicite qu'on tente
/// de lui imposer. Une AudioUnit HAL (`kAudioUnitSubType_HALOutput`), elle, respecte le
/// `kAudioOutputUnitProperty_CurrentDevice` qu'on lui donne → on peut la brancher sur NOTRE
/// agrégat { sortie réelle + BlackHole }.
///
/// Notions Core Audio :
/// - Une AUHAL en mode FULL-DUPLEX gère entrée (element 1) ET sortie (element 0) sur le MÊME
///   périphérique. On l'active des deux côtés (`EnableIO`).
/// - On installe un **render callback** côté sortie : le système l'appelle quand il a besoin
///   d'échantillons à jouer. Dans ce callback on tire d'abord l'entrée (`AudioUnitRender` sur
///   l'element 1), on l'écrit dans une ligne à retard, et on remplit la sortie avec les
///   échantillons d'il y a `delayFrames` images.
/// - Comme entrée et sortie partagent l'horloge de l'agrégat, la ligne à retard ne dérive
///   jamais : le délai = simple décalage entre l'écriture et la lecture dans un buffer circulaire.
final class DelayAudioEngine {

    private var audioUnit: AudioUnit?
    private(set) var isRunning = false

    /// Niveau crête (0…1) du son capturé sur l'entrée, mis à jour à chaque render callback.
    /// Écrit dans le thread temps réel, lu sur le main pour le VU-mètre (lecture d'un Float
    /// non bloquante : un déchirement éventuel est sans conséquence pour un indicateur visuel).
    var inputLevel: Float = 0

    // MARK: - Ligne à retard (buffer circulaire, 2 canaux)

    /// Taille du buffer circulaire en images : 2 s à 48 kHz, large pour couvrir 0–1000 ms.
    private let ringCapacity = 96_000
    private var ringL: UnsafeMutablePointer<Float>?
    private var ringR: UnsafeMutablePointer<Float>?
    private var writePos = 0

    /// Buffer réutilisé pour tirer l'entrée dans le callback (alloué une fois, pas dans le RT thread).
    private var inputABL: UnsafeMutableAudioBufferListPointer?
    private let maxFramesPerSlice = 4096

    private var sampleRate: Double = 48_000

    /// Retard courant en IMAGES (lu dans le thread temps réel ; un Int se lit/écrit atomiquement).
    private var delayFrames = 0
    private var delayMsValue: Double = 0

    /// Délai en millisecondes. Modifiable PENDANT la lecture (le callback relit `delayFrames`).
    var delayMilliseconds: Double {
        get { delayMsValue }
        set {
            delayMsValue = max(0, newValue)
            let frames = Int(delayMsValue / 1000.0 * sampleRate)
            delayFrames = min(max(0, frames), ringCapacity - 1)
        }
    }

    // MARK: - Cycle de vie

    /// Démarre la chaîne sur l'agrégat `aggregateDeviceID`.
    /// - Parameters:
    ///   - aggregateDeviceID: agrégat { sortie réelle (canaux 0,1) + BlackHole (entrée) }.
    ///   - outputChannelMap: routage des canaux de sortie (ex. `[0,1,-1,-1]` = stéréo vers la
    ///     sortie réelle, silence sur les canaux de BlackHole).
    func start(aggregateDeviceID: AudioDeviceID, outputChannelMap: [Int32]) throws {
        guard !isRunning else { return }

        // 1) Instancier l'AUHAL.
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw DelayEngineError.componentUnavailable
        }
        var unitOpt: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &unitOpt), "instanciation")
        guard let unit = unitOpt else { throw DelayEngineError.componentUnavailable }
        audioUnit = unit

        // 2) Activer entrée (element 1) ET sortie (element 0).
        var enable: UInt32 = 1
        try setProp(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                    &enable, UInt32(MemoryLayout<UInt32>.size), "EnableIO entrée")
        try setProp(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                    &enable, UInt32(MemoryLayout<UInt32>.size), "EnableIO sortie")

        // 3) Brancher NOTRE agrégat (l'AUHAL respecte cette propriété, contrairement à AVAudioEngine).
        var device = aggregateDeviceID
        try setProp(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                    &device, UInt32(MemoryLayout<AudioDeviceID>.size), "CurrentDevice")

        // 4) Récupérer la fréquence d'échantillonnage de l'agrégat (master = BlackHole).
        sampleRate = nominalSampleRate(of: aggregateDeviceID) ?? 48_000

        // 5) Imposer un format canonique : float 32, non entrelacé, 2 canaux, à `sampleRate`.
        var asbd = canonicalFormat(sampleRate: sampleRate, channels: 2)
        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        // Format de ce qu'on REÇOIT de l'entrée (sortie de l'element 1).
        try setProp(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                    &asbd, asbdSize, "format entrée")
        // Format de ce qu'on FOURNIT à la sortie (entrée de l'element 0).
        try setProp(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                    &asbd, asbdSize, "format sortie")

        // 6) Carte de canaux de sortie : router nos 2 canaux vers la sortie réelle uniquement.
        if !outputChannelMap.isEmpty {
            var map = outputChannelMap
            try setProp(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 0,
                        &map, UInt32(map.count * MemoryLayout<Int32>.size), "carte de canaux")
        }

        // 7) Limiter la taille de tranche, allouer la ligne à retard et le buffer d'entrée.
        var maxFrames = UInt32(maxFramesPerSlice)
        try setProp(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                    &maxFrames, UInt32(MemoryLayout<UInt32>.size), "MaximumFramesPerSlice")
        allocateBuffers()

        // 8) Installer le render callback (côté entrée de la sortie : element 0, scope Input).
        var cb = AURenderCallbackStruct(
            inputProc: delayRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try setProp(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                    &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size), "render callback")

        // 9) Recalculer delayFrames maintenant que sampleRate est connu, puis démarrer.
        delayMilliseconds = delayMsValue

        try check(AudioUnitInitialize(unit), "init", wrap: DelayEngineError.initFailed)
        try check(AudioOutputUnitStart(unit), "start", wrap: DelayEngineError.startFailed)
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        audioUnit = nil
        freeBuffers()
        writePos = 0
        inputLevel = 0
        isRunning = false
    }

    // MARK: - Rendu temps réel

    /// Appelé par le callback C. Tire l'entrée, l'écrit dans la ligne à retard, remplit la sortie.
    fileprivate func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            _ timeStamp: UnsafePointer<AudioTimeStamp>,
                            _ frames: UInt32,
                            _ outputABL: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let unit = audioUnit,
              let inputABL = inputABL,
              let ringL = ringL, let ringR = ringR,
              let outputABL = outputABL else { return noErr }

        let n = Int(frames)

        // (a) Tirer l'entrée (BlackHole) dans notre buffer réutilisable.
        for i in 0..<inputABL.count {
            inputABL[i].mDataByteSize = frames * 4
            inputABL[i].mNumberChannels = 1
        }
        let status = AudioUnitRender(unit, flags, timeStamp, 1, frames, inputABL.unsafeMutablePointer)
        let outBuffers = UnsafeMutableAudioBufferListPointer(outputABL)

        // En cas d'échec de capture, sortir du silence (évite le bruit).
        guard status == noErr else {
            for b in 0..<outBuffers.count {
                if let d = outBuffers[b].mData { memset(d, 0, Int(frames) * 4) }
            }
            return noErr
        }

        let inL = inputABL[0].mData?.assumingMemoryBound(to: Float.self)
        let inR = (inputABL.count > 1 ? inputABL[1].mData : inputABL[0].mData)?
            .assumingMemoryBound(to: Float.self)
        let outL = outBuffers.count > 0 ? outBuffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
        let outR = outBuffers.count > 1 ? outBuffers[1].mData?.assumingMemoryBound(to: Float.self) : outL

        let delay = delayFrames
        let cap = ringCapacity
        var w = writePos
        var peak: Float = 0

        for i in 0..<n {
            // Écrire l'échantillon courant.
            let l = inL?[i] ?? 0
            let r = inR?[i] ?? 0
            ringL[w] = l
            ringR[w] = r
            peak = max(peak, max(abs(l), abs(r)))
            // Lire l'échantillon retardé (w - delay), modulo capacité.
            let rp = (w - delay + cap) % cap
            outL?[i] = ringL[rp]
            outR?[i] = ringR[rp]
            w = (w + 1) % cap
        }
        writePos = w
        inputLevel = peak
        return noErr
    }

    // MARK: - Allocation

    private func allocateBuffers() {
        ringL = .allocate(capacity: ringCapacity)
        ringR = .allocate(capacity: ringCapacity)
        ringL?.initialize(repeating: 0, count: ringCapacity)
        ringR?.initialize(repeating: 0, count: ringCapacity)
        writePos = 0

        // Buffer d'entrée : 2 canaux non entrelacés.
        let abl = AudioBufferList.allocate(maximumBuffers: 2)
        for i in 0..<abl.count {
            abl[i].mNumberChannels = 1
            abl[i].mDataByteSize = UInt32(maxFramesPerSlice * 4)
            abl[i].mData = UnsafeMutableRawPointer.allocate(
                byteCount: maxFramesPerSlice * 4, alignment: MemoryLayout<Float>.alignment)
        }
        inputABL = abl
    }

    private func freeBuffers() {
        ringL?.deallocate(); ringL = nil
        ringR?.deallocate(); ringR = nil
        if let abl = inputABL {
            for i in 0..<abl.count { abl[i].mData?.deallocate() }
            free(abl.unsafeMutablePointer)
            inputABL = nil
        }
    }

    // MARK: - Helpers Core Audio

    private func canonicalFormat(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
    }

    private func nominalSampleRate(of device: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var sr: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &sr) == noErr, sr > 0 else {
            return nil
        }
        return sr
    }

    private func setProp(_ unit: AudioUnit, _ id: AudioUnitPropertyID, _ scope: AudioUnitScope,
                         _ element: AudioUnitElement, _ data: UnsafeMutableRawPointer,
                         _ size: UInt32, _ name: String) throws {
        let status = AudioUnitSetProperty(unit, id, scope, element, data, size)
        guard status == noErr else {
            throw DelayEngineError.couldNotSetProperty(name: name, status: status)
        }
    }

    private func check(_ status: OSStatus, _ what: String,
                       wrap: ((OSStatus) -> DelayEngineError)? = nil) throws {
        guard status != noErr else { return }
        throw wrap?(status) ?? DelayEngineError.couldNotSetProperty(name: what, status: status)
    }
}

/// Callback C temps réel : récupère l'instance via `inRefCon` et délègue à `render`.
private func delayRenderCallback(inRefCon: UnsafeMutableRawPointer,
                                 ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                                 inTimeStamp: UnsafePointer<AudioTimeStamp>,
                                 inBusNumber: UInt32,
                                 inNumberFrames: UInt32,
                                 ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let engine = Unmanaged<DelayAudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    return engine.render(ioActionFlags, inTimeStamp, inNumberFrames, ioData)
}
