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

    /// Meldet Beginn und Ende des Vorhoerens. Das Einstellungsfenster
    /// beschriftet seinen Knopf danach und koennte das Ende nicht selbst
    /// erkennen: der Ton hoert nach seiner Laufzeit von allein auf, und ein
    /// Timer auf gut Glueck laege bei jedem eigenen Alarmton daneben.
    ///
    /// `@MainActor` steht im Typ, weil `audioPlayerDidFinishPlaying` keine
    /// Zusage ueber seinen Thread macht — `notifyPreviewState(_:)` loest das
    /// hier ein, damit es nicht jeder Empfaenger einzeln tun muss.
    var onPreviewStateChanged: (@MainActor @Sendable (Bool) -> Void)?

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Laeuft gerade ein Vorhoeren? Fuer ein Fenster, das waehrenddessen
    /// geoeffnet wird und den laufenden Ton sonst nicht kennte.
    var isPreviewing: Bool { previewPlayer != nil }

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

        // Scheitert das Laden, laeuft nichts — und der Knopf muss das erfahren,
        // sonst bliebe er auf "Test stoppen" stehen.
        guard let url = try? soundURL(for: settings) else {
            notifyPreviewState(false)
            return
        }
        // Gleiche Reihenfolge wie in `start(settings:)`: erst laden, dann laut.
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            notifyPreviewState(false)
            return
        }
        newPlayer.numberOfLoops = 0   // genau einmal, kein Alarm
        newPlayer.volume = 1.0
        newPlayer.delegate = self
        newPlayer.prepareToPlay()

        volumeController.raise(to: settings.minimumVolume)
        previewPlayer = newPlayer
        newPlayer.play()
        notifyPreviewState(true)
    }

    /// Bricht das Vorhoeren ab. Seit der Knopf im Einstellungsfenster ein
    /// Umschalter ist, kommt der Aufruf auch von dort — und damit erstmals
    /// zu einem Zeitpunkt, an dem ein echter Alarm laufen kann.
    func stopPreview() {
        guard previewPlayer != nil else { return }
        previewPlayer?.stop()
        previewPlayer = nil
        // Dieselbe Ruecksicht wie am natuerlichen Ende: laeuft inzwischen ein
        // Alarm, gehoert der Snapshot ihm, und ein `restore()` hier drehte den
        // laufenden Alarm leise. Aus `preview(settings:)` gerufen ist `player`
        // immer nil — der Neustart bekommt seinen Snapshot also weiterhin frei.
        if player == nil { volumeController.restore() }
        notifyPreviewState(false)
    }

    /// Wird nur beim natuerlichen Ende gerufen; `stop()` loest sie nicht aus.
    /// Deshalb steht hier die Wiederherstellung und kein geratener Timer.
    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        guard finished === previewPlayer else { return }
        previewPlayer = nil
        // Ein Alarm kann waehrend der 2,4 Sekunden losgegangen sein. Dann
        // gehoert der Snapshot ihm, und ein `restore()` hier drehte den
        // laufenden Alarm leise. Der Alarm raeumt selbst auf.
        if player == nil { volumeController.restore() }
        // Hierdurch faellt der Knopf von allein auf "Ton testen" zurueck.
        notifyPreviewState(false)
    }

    /// Immer auf dem Hauptthread: die Rueckmeldung von `AVAudioPlayer` kommt
    /// zwar auf dem Thread, der abgespielt hat — hier also dem Hauptthread —,
    /// aber zugesagt ist das nirgends, und der Empfaenger ist die Oberflaeche.
    private func notifyPreviewState(_ playing: Bool) {
        guard let notify = onPreviewStateChanged else { return }
        Task { @MainActor in notify(playing) }
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
