import AVFoundation
import Combine
import CoreAudio
import SwiftUI

/// Pont entre l'UI SwiftUI et les services audio.
///
/// `@MainActor` : tout l'état publié est manipulé sur le thread principal (l'UI lit/écrit
/// ces propriétés). `ObservableObject` + `@Published` : SwiftUI se redessine automatiquement
/// quand une de ces propriétés change.
@MainActor
final class AudioDelayViewModel: ObservableObject {

    // Listes pour les sélecteurs.
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []

    // Sélections courantes (on stocke l'ID runtime, source de vérité côté Core Audio).
    // Le `didSet` persiste l'UID STABLE du périphérique (l'ID, lui, change entre deux lancements).
    @Published var selectedInputID: AudioDeviceID? {
        didSet { persistSelection(selectedInputID, in: inputDevices, key: Self.inputUIDKey) }
    }
    @Published var selectedOutputID: AudioDeviceID? {
        didSet { persistSelection(selectedOutputID, in: outputDevices, key: Self.outputUIDKey) }
    }

    private static let inputUIDKey = "audioDelay.inputUID"
    private static let outputUIDKey = "audioDelay.outputUID"

    /// Clé `UserDefaults` pour persister le délai entre deux lancements de l'app.
    private static let delayKey = "audioDelay.delayMs"

    /// Délai en ms, lié au slider/stepper. Le `didSet` répercute en direct sur l'engine et
    /// **persiste** la valeur (rechargée au prochain lancement). La valeur initiale est relue
    /// depuis `UserDefaults` (0 par défaut si jamais réglée).
    @Published var delayMs: Double = UserDefaults.standard.double(forKey: AudioDelayViewModel.delayKey) {
        didSet {
            engine.delayMilliseconds = delayMs
            UserDefaults.standard.set(delayMs, forKey: Self.delayKey)
        }
    }

    @Published var isRunning = false
    @Published var statusMessage = "Ready."
    @Published var errorMessage: String?

    private let engine = DelayAudioEngine()
    private let aggregateService = AggregateDeviceService()

    /// Niveau crête courant (0…1) du son capturé, pour le VU-mètre. Lu à la demande par la vue
    /// (via un `TimelineView` local) — surtout PAS publié, pour ne pas redessiner tout l'écran.
    var inputLevel: Float { engine.inputLevel }

    // MARK: - Périphériques

    /// (Re)charge la liste des périphériques et présélectionne intelligemment.
    func refreshDevices() {
        let all = AudioDeviceService.allDevices()
        inputDevices = all.filter(\.hasInput)
        outputDevices = all.filter(\.hasOutput)

        // Entrée : on préfère le dernier périphérique mémorisé (par UID), puis BlackHole (la
        // source qu'on veut retarder), puis l'entrée par défaut.
        if selectedInputID == nil || !inputDevices.contains(where: { $0.id == selectedInputID }) {
            let blackHole = inputDevices.first { $0.name.localizedCaseInsensitiveContains("blackhole") }
            selectedInputID = savedDeviceID(forKey: Self.inputUIDKey, in: inputDevices)
                ?? blackHole?.id
                ?? AudioDeviceService.defaultInputDeviceID()
                ?? inputDevices.first?.id
        }

        // Sortie : on préfère le dernier périphérique mémorisé (par UID), puis la sortie par défaut.
        if selectedOutputID == nil || !outputDevices.contains(where: { $0.id == selectedOutputID }) {
            selectedOutputID = savedDeviceID(forKey: Self.outputUIDKey, in: outputDevices)
                ?? AudioDeviceService.defaultOutputDeviceID()
                ?? outputDevices.first?.id
        }
    }

    /// Re-résout un UID mémorisé vers l'`AudioDeviceID` courant (l'ID change entre deux lancements,
    /// pas l'UID). Renvoie nil si le périphérique n'est plus présent.
    private func savedDeviceID(forKey key: String, in devices: [AudioDevice]) -> AudioDeviceID? {
        guard let uid = UserDefaults.standard.string(forKey: key) else { return nil }
        return devices.first(where: { $0.uid == uid })?.id
    }

    /// Persiste l'UID du périphérique sélectionné (clé stable, contrairement à l'ID runtime).
    private func persistSelection(_ id: AudioDeviceID?, in devices: [AudioDevice], key: String) {
        guard let id, let uid = devices.first(where: { $0.id == id })?.uid, !uid.isEmpty else { return }
        UserDefaults.standard.set(uid, forKey: key)
    }

    // MARK: - Start / Stop

    func toggle() {
        isRunning ? stop() : start()
    }

    private func start() {
        errorMessage = nil

        guard let inputID = selectedInputID,
              let inputDevice = inputDevices.first(where: { $0.id == inputID }) else {
            errorMessage = "Choose an input device."
            return
        }
        guard let outputID = selectedOutputID else {
            errorMessage = "Choose an output device."
            return
        }

        // Capturer l'audio nécessite l'autorisation micro (TCC). On la demande, puis on
        // démarre une fois accordée.
        requestMicrophoneAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.errorMessage = "Microphone access denied. Settings › Privacy & Security › Microphone."
                return
            }
            self.startEngine(inputDevice: inputDevice, outputID: outputID)
        }
    }

    private func startEngine(inputDevice: AudioDevice, outputID: AudioDeviceID) {
        guard let outputDevice = outputDevices.first(where: { $0.id == outputID }) else {
            errorMessage = "Output device not found."
            return
        }

        // Le provider reste l'abstraction swappable de la SOURCE (BlackHole aujourd'hui,
        // process tap demain) ; il fournit le périphérique à capturer.
        let provider: AudioCaptureProvider = DeviceInputCaptureProvider(device: inputDevice)
        do {
            _ = try provider.activate()

            // On regroupe sortie réelle + BlackHole dans UN agrégat à horloge unique. L'AudioUnit
            // HAL s'y branche directement. La sortie réelle est en 1ʳᵉ position → canaux 0,1.
            let aggID = try aggregateService.create(outputUID: outputDevice.uid,
                                                     inputUID: inputDevice.uid)

            // Carte de canaux : stéréo de l'engine → uniquement les canaux de la sortie réelle.
            let totalOut = AudioDeviceService.device(for: aggID)?.outputChannels
                ?? (outputDevice.outputChannels + inputDevice.outputChannels)
            var channelMap = [Int32](repeating: -1, count: max(totalOut, 2))
            let usable = min(2, outputDevice.outputChannels)
            for i in 0..<usable { channelMap[i] = Int32(i) }

            try engine.start(aggregateDeviceID: aggID, outputChannelMap: channelMap)
            engine.delayMilliseconds = delayMs   // appliquer le délai courant dès le départ
            isRunning = true
            statusMessage = "Playing — \(inputDevice.name) → \(outputDevice.name), delay \(Int(delayMs)) ms."
        } catch {
            engine.stop()
            aggregateService.destroy()
            provider.deactivate()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Stopped."
        }
    }

    private func stop() {
        engine.stop()
        aggregateService.destroy()   // l'agrégat est privé et éphémère : on le retire à l'arrêt.
        isRunning = false
        statusMessage = "Stopped."
    }

    // MARK: - Ajustements fins du délai

    func nudgeDelay(by deltaMs: Double) {
        delayMs = min(1000, max(0, (delayMs + deltaMs).rounded()))
    }

    // MARK: - Autorisation micro

    private func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                // Le callback arrive sur un thread arbitraire → on repasse sur le main.
                Task { @MainActor in completion(granted) }
            }
        default:
            completion(false)
        }
    }
}
