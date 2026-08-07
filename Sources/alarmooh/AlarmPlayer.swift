import AlarmoohCore
import AVFoundation
import Foundation

/// Spielt den Alarmton in Endlosschleife, bis `stop()` gerufen wird.
final class AlarmPlayer {
    private var player: AVAudioPlayer?
    private let volumeController = SystemVolumeController()

    var isPlaying: Bool { player?.isPlaying ?? false }

    func start(settings: Settings) {
        stop()
        guard let url = try? soundURL(for: settings) else { return }

        // Reihenfolge ist Absicht: erst den Player bauen, dann die Lautstaerke
        // anheben. Scheitert das Laden (kaputte oder ausgetauschte Datei),
        // bleibt die Systemlautstaerke unangetastet - sonst haetten wir ein
        // lautes Geraet, das nichts abspielt und nichts mehr leiser dreht.
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        newPlayer.numberOfLoops = -1   // endlos, wie im Design festgelegt
        newPlayer.volume = 1.0
        newPlayer.prepareToPlay()

        volumeController.raise(to: settings.minimumVolume)
        player = newPlayer
        newPlayer.play()
    }

    func stop() {
        player?.stop()
        player = nil
        volumeController.restore()
    }

    func restoreVolumeAfterCrashIfNeeded() {
        volumeController.restoreAfterCrashIfNeeded()
    }

    /// Eigene Datei des Nutzers, sonst der erzeugte Ersatzton.
    private func soundURL(for settings: Settings) throws -> URL {
        if let path = settings.soundPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let support = SettingsStore.supportDirectory()
        // Neuer Name, weil der Ersatzton nur erzeugt wird, wenn die Datei fehlt:
        // wer den alten Ton schon einmal gehoert hat, behielte ihn sonst ewig.
        try? FileManager.default.removeItem(at: support.appendingPathComponent("fallback-tone.wav"))
        let fallback = support.appendingPathComponent("fallback-tone-2.wav")
        if !FileManager.default.fileExists(atPath: fallback.path) {
            try FileManager.default.createDirectory(
                at: fallback.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try ToneGenerator.writeFallbackTone(to: fallback)
        }
        return fallback
    }
}
