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
    func restoreAfterCrashIfNeeded() {
        guard let snapshot = snapshots.load() else { return }
        apply(snapshot)
        snapshots.clear()
    }

    func raise(to minimum: Float) {
        guard let current = currentSnapshot() else { return }
        activeSnapshot = current
        try? snapshots.save(current)
        if current.muted { setMuted(false) }
        if current.volume < minimum { setVolume(minimum) }
    }

    func restore() {
        guard let snapshot = activeSnapshot ?? snapshots.load() else { return }
        apply(snapshot)
        activeSnapshot = nil
        snapshots.clear()
    }

    private func apply(_ snapshot: VolumeSnapshot) {
        setVolume(snapshot.volume)
        setMuted(snapshot.muted)
    }

    private func currentSnapshot() -> VolumeSnapshot? {
        guard let volume = getVolume() else { return nil }
        return VolumeSnapshot(volume: volume, muted: getMuted() ?? false)
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
        return status == noErr ? deviceID : nil
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

    private func getVolume() -> Float? {
        guard let device = outputDevice else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress()
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func setVolume(_ value: Float) {
        guard let device = outputDevice else { return }
        var newValue = Float32(min(max(value, 0), 1))
        var address = volumeAddress()
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &newValue
        )
    }

    private func getMuted() -> Bool? {
        guard let device = outputDevice else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress()
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value == 1 : nil
    }

    private func setMuted(_ muted: Bool) {
        guard let device = outputDevice else { return }
        var value: UInt32 = muted ? 1 : 0
        var address = muteAddress()
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }
}
