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
        volumeController.raise(to: settings.minimumVolume)

        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1   // endlos, wie im Design festgelegt
        player?.volume = 1.0
        player?.prepareToPlay()
        player?.play()
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
        let fallback = SettingsStore.supportDirectory().appendingPathComponent("fallback-tone.wav")
        if !FileManager.default.fileExists(atPath: fallback.path) {
            try FileManager.default.createDirectory(
                at: fallback.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try ToneGenerator.writeFallbackTone(to: fallback)
        }
        return fallback
    }
}
