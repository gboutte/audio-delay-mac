import AVFoundation
import Combine

/// Métronome de calibration : une **barre balaie de droite à gauche** et, à chaque fois qu'elle
/// atteint le repère (bord gauche), un **clic sonore** est émis. La barre rend le battement
/// *prédictible* (on le voit arriver), contrairement à un flash.
///
/// Le clic part vers la sortie système (= BlackHole) → il traverse le délai de l'app. Le balayage
/// est affiché à l'écran → retardé par le cast vidéo vers le projecteur. On règle le délai jusqu'à
/// ce que le clic entendu tombe pile quand la barre touche le repère sur le projecteur.
///
/// Choix techniques pour un timing régulier :
/// - **Visuel** : on ne stocke pas une position ; la vue interroge `phase(at:)` via `TimelineView`
///   à chaque image. La position se déduit du temps écoulé depuis `startDate` → fluide, sans jitter.
/// - **Audio** : chaque clic est reprogrammé à une **heure absolue** (`startDate + k·période`),
///   donc sans dérive cumulée (contrairement à un `Timer` répétitif).
@MainActor
final class MetronomeController: ObservableObject {

    @Published var bpm: Double = 60 {
        didSet { if isRunning { restart() } }
    }
    @Published private(set) var isRunning = false

    /// Origine temporelle commune au visuel et à l'audio (battement 0).
    private(set) var startDate = Date()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?

    private var beatIndex = 0
    private var clickTimer: Timer?

    init() {
        buildClickAndGraph()
    }

    /// Période d'un battement en secondes.
    var period: TimeInterval { 60.0 / max(20.0, min(240.0, bpm)) }

    /// Phase courante (0…1) du balayage à l'instant `date` : 0 = battement (barre au repère).
    func phase(at date: Date) -> Double {
        guard isRunning else { return 0 }
        let p = date.timeIntervalSince(startDate) / period
        let frac = p - p.rounded(.down)
        return max(0, min(1, frac))
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning, clickBuffer != nil else { return }
        do {
            try engine.start()
            player.play()
            startDate = Date()
            beatIndex = 0
            isRunning = true
            playClick()          // battement 0, tout de suite
            scheduleNextBeat()   // puis 1, 2, 3… à heure absolue
        } catch {
            isRunning = false
        }
    }

    func stop() {
        clickTimer?.invalidate()
        clickTimer = nil
        player.stop()
        engine.stop()
        isRunning = false
    }

    // MARK: - Privé

    private func restart() {
        clickTimer?.invalidate()
        startDate = Date()
        beatIndex = 0
        playClick()
        scheduleNextBeat()
    }

    /// Programme le prochain battement à son heure absolue (anti-dérive), qui se reprogramme lui-même.
    private func scheduleNextBeat() {
        beatIndex += 1
        let fireDate = startDate.addingTimeInterval(Double(beatIndex) * period)
        let t = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.playClick()
                self.scheduleNextBeat()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        clickTimer = t
    }

    private func playClick() {
        guard let buffer = clickBuffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Construit le buffer de clic (sinus 1 kHz à décroissance rapide) et le graphe audio.
    private func buildClickAndGraph() {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(sampleRate * 0.05)) else {
            return
        }
        let frames = Int(sampleRate * 0.05) // 50 ms
        buffer.frameLength = AVAudioFrameCount(frames)
        for ch in 0..<Int(format.channelCount) {
            guard let p = buffer.floatChannelData?[ch] else { continue }
            for i in 0..<frames {
                let t = Double(i) / sampleRate
                let envelope = exp(-t * 35.0)
                p[i] = Float(sin(2.0 * .pi * 1000.0 * t) * envelope * 0.6)
            }
        }
        clickBuffer = buffer
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }
}
