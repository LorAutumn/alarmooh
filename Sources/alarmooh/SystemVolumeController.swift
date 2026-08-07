import AlarmoohCore
// kAudioHardwareServiceDeviceProperty_VirtualMainVolume steht in AudioToolbox,
// nicht in CoreAudio; gelesen und geschrieben wird es ueber die AudioObject-API.
import AudioToolbox
import CoreAudio
import Foundation

/// Hebt die Ausgabelautstaerke fuer die Dauer eines Alarms an und stellt den
/// vorherigen Zustand danach wieder her.
final class SystemVolumeController {
    private let snapshots = VolumeSnapshotStore.standard()

    /// Zweite Kopie des Snapshots im Speicher. Das Schreiben der Datei kann
    /// fehlschlagen (Platte voll, fehlende Rechte, Pfad ist ein Verzeichnis);
    /// die Datei ist nur fuer den Absturzfall da, weil sie den Prozess
    /// ueberlebt. Innerhalb einer Prozesslaufzeit macht erst diese Kopie
    /// `restore()` verlaesslich.
    private var activeSnapshot: VolumeSnapshot?

    /// Beim Start aufrufen: Falls ein Alarm durch einen Absturz beendet wurde,
    /// steht die Lautstaerke noch oben.
    ///
    /// Die Datei wird nur geloescht, wenn sie auch angewandt wurde — sonst
    /// waere der einzige Hinweis auf ein noch lautes Geraet weg, ohne dass
    /// jemand es leiser gedreht haette. Siehe `apply(_:)`.
    func restoreAfterCrashIfNeeded() {
        guard let snapshot = snapshots.load() else { return }
        if apply(snapshot) { snapshots.clear() }
    }

    func raise(to minimum: Float) {
        // Zweites `raise()` ohne `restore()` dazwischen: der gemerkte Zustand
        // ist bereits der originale des Nutzers. Wuerden wir jetzt neu messen,
        // schrieben wir die schon angehobene Lautstaerke als "vorher" fest und
        // koennten sie nie wieder zuruecksetzen.
        guard activeSnapshot == nil else { return }
        // Ein einziges Mal aufgeloest und dann durchgereicht: `outputDevice`
        // fragt das System bei jedem Zugriff neu. Zwischen zwei Zugriffen kann
        // das Standardgeraet wechseln — dann stammten Lautstaerke und
        // Stummschaltung eines Snapshots von zwei verschiedenen Geraeten.
        guard let device = outputDevice, let current = currentSnapshot(of: device) else { return }
        activeSnapshot = current
        try? snapshots.save(current)
        if current.muted { setMuted(false, on: device) }
        if current.volume < minimum { setVolume(minimum, on: device) }
    }

    func restore() {
        guard let snapshot = activeSnapshot ?? snapshots.load() else { return }
        let restored = apply(snapshot)
        // Der Snapshot im Speicher geht in jedem Fall weg: er ist der Grund,
        // aus dem `raise()` nicht erneut misst, und bliebe er stehen, liesse
        // der naechste Alarm die Lautstaerke unangetastet und koennte sie auch
        // nicht mehr zuruecksetzen.
        activeSnapshot = nil
        // Die Datei dagegen bleibt liegen, wenn nichts geschrieben wurde. Sie
        // ist dann das Einzige, was den urspruenglichen Zustand des anderen
        // Geraets noch kennt: liegt es beim naechsten Start wieder vorn, dreht
        // `restoreAfterCrashIfNeeded` es leiser. Ein neuer Alarm ueberschreibt
        // sie — zu Recht, denn der misst das dann aktuelle Geraet neu.
        if restored { snapshots.clear() }
    }

    /// Schreibt den gemerkten Zustand zurueck. Gibt zurueck, ob das geschehen
    /// ist.
    ///
    /// Der Geraeteabgleich davor ist kein Beiwerk: `outputDevice` liefert immer
    /// das *aktuelle* Standardgeraet. Wechselt es waehrend des Alarms — Kopfhoerer
    /// aufgesetzt —, schriebe ein blindes `restore()` die gemerkte Lautstaerke
    /// des alten Geraets auf das neue. Aus 100 % Notebooklautsprecher von gestern
    /// Abend wuerden so 100 % im Ohr.
    ///
    /// Kennt der Snapshot kein Geraet (Datei einer aelteren Version), wird
    /// trotzdem zurueckgeschrieben: nichts zu tun waere schlechter als der
    /// bisherige Stand, und der bisherige Stand ist genau dieses blinde
    /// Zurueckschreiben. Laesst sich umgekehrt das aktuelle Geraet nicht
    /// benennen, obwohl der Snapshot eines nennt, bleibt es beim Nichtstun —
    /// dann ist gerade nicht feststellbar, dass es dasselbe ist.
    private func apply(_ snapshot: VolumeSnapshot) -> Bool {
        guard let device = outputDevice else { return false }
        if let recorded = snapshot.deviceUID, recorded != deviceUID(of: device) {
            log.info("Ausgabegeraet gewechselt, Lautstaerke wird nicht zurueckgesetzt")
            return false
        }
        setVolume(snapshot.volume, on: device)
        setMuted(snapshot.muted, on: device)
        return true
    }

    private func currentSnapshot(of device: AudioObjectID) -> VolumeSnapshot? {
        guard let volume = getVolume(of: device) else { return nil }
        return VolumeSnapshot(
            volume: volume, muted: getMuted(of: device) ?? false, deviceUID: deviceUID(of: device)
        )
    }

    // MARK: - CoreAudio

    private var outputDevice: AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        // `kAudioObjectUnknown` kommt auch mit `noErr` vor (kein Ausgabegeraet
        // vorhanden) und waere als Ziel eines Schreibzugriffs sinnlos.
        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    /// Die geraetefeste Kennung, etwa "BuiltInSpeakerDevice". Anders als die
    /// `AudioObjectID` bleibt sie ueber Systemstarts hinweg dieselbe — nur
    /// deshalb taugt sie fuer einen Snapshot, der auf der Platte liegt.
    private func deviceUID(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // CoreAudio gibt den String mit +1 heraus; `takeRetainedValue`
        // uebernimmt ihn, ohne ihn ein zweites Mal zu halten.
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func getVolume(of device: AudioObjectID) -> Float? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress()
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func setVolume(_ value: Float, on device: AudioObjectID) {
        var newValue = Float32(min(max(value, 0), 1))
        var address = volumeAddress()
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &newValue
        )
    }

    private func getMuted(of device: AudioObjectID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress()
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value == 1 : nil
    }

    private func setMuted(_ muted: Bool, on device: AudioObjectID) {
        var value: UInt32 = muted ? 1 : 0
        var address = muteAddress()
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }
}
