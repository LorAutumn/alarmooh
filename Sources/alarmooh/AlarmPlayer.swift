import AlarmoohCore
import AVFoundation
import Foundation

/// Spielt den Alarmton in Endlosschleife, bis `stop()` gerufen wird.
final class AlarmPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    /// Eigener Player fuers Vorhoeren. Bewusst nicht `player`: sonst haelte
    /// `stop()` das Vorhoeren fuer einen Alarm und `isPlaying` meldete einen,
    /// der gar nicht laeuft.
    private var previewPlayer: AVAudioPlayer?
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

    // MARK: - Vorhoeren

    /// Spielt den Ton genau einmal, damit der Nutzer die eingestellte
    /// Mindestlautstaerke pruefen kann, ohne auf einen echten Alarm zu warten.
    /// Die Lautstaerke wird dafuer genauso angehoben wie beim Alarm — sonst
    /// hoerte man irgendeinen Pegel, nur nicht den eingestellten.
    func preview(settings: Settings) {
        // Waehrend eines echten Alarms passiert nichts: der Alarm hat den
        // Snapshot der Lautstaerke, und ein Vorhoeren daneben brauchte niemand.
        guard player == nil else { return }
        // Zweiter Klick startet neu, mit dem inzwischen eingestellten Wert.
        // Dafuer muss der alte Snapshot zurueck, bevor neu angehoben wird:
        // `raise(to:)` ueberschreibt einen bestehenden Snapshot absichtlich nicht.
        stopPreview()

        guard let url = try? soundURL(for: settings) else { return }
        // Gleiche Reihenfolge wie in `start(settings:)`: erst laden, dann laut.
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        newPlayer.numberOfLoops = 0   // genau einmal, kein Alarm
        newPlayer.volume = 1.0
        newPlayer.delegate = self
        newPlayer.prepareToPlay()

        volumeController.raise(to: settings.minimumVolume)
        previewPlayer = newPlayer
        newPlayer.play()
    }

    private func stopPreview() {
        guard previewPlayer != nil else { return }
        previewPlayer?.stop()
        previewPlayer = nil
        volumeController.restore()
    }

    /// Wird nur beim natuerlichen Ende gerufen; `stop()` loest sie nicht aus.
    /// Deshalb steht hier die Wiederherstellung und kein geratener Timer.
    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        guard finished === previewPlayer else { return }
        previewPlayer = nil
        // Ein Alarm kann waehrend der 2,4 Sekunden losgegangen sein. Dann
        // gehoert der Snapshot ihm, und ein `restore()` hier drehte den
        // laufenden Alarm leise. Der Alarm raeumt selbst auf.
        guard player == nil else { return }
        volumeController.restore()
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
