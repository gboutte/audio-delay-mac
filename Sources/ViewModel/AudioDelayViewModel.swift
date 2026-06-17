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

    // Sélections courantes (on stocke l'ID, source de vérité côté Core Audio).
    @Published var selectedInputID: AudioDeviceID?
    @Published var selectedOutputID: AudioDeviceID?

    /// Délai en ms, lié au slider/stepper. Le `didSet` répercute en direct sur l'engine,
    /// ce qui permet d'ajuster pendant la lecture.
    @Published var delayMs: Double = 0 {
        didSet { engine.delayMilliseconds = delayMs }
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

        // Entrée : on privilégie BlackHole si présent (c'est la source qu'on veut retarder),
        // sinon l'entrée par défaut.
        if selectedInputID == nil || !inputDevices.contains(where: { $0.id == selectedInputID }) {
            let blackHole = inputDevices.first { $0.name.localizedCaseInsensitiveContains("blackhole") }
            selectedInputID = blackHole?.id
                ?? AudioDeviceService.defaultInputDeviceID()
                ?? inputDevices.first?.id
        }

        // Sortie : sortie par défaut, sinon la première (l'utilisateur choisira son ampli BT).
        if selectedOutputID == nil || !outputDevices.contains(where: { $0.id == selectedOutputID }) {
            selectedOutputID = AudioDeviceService.defaultOutputDeviceID()
                ?? outputDevices.first?.id
        }
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
