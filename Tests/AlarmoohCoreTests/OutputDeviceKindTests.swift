import CoreAudio
import Testing
@testable import AlarmoohCore

private func kind(
    _ transportType: UInt32, dataSource: UInt32? = nil, terminalType: UInt32? = nil
) -> OutputDeviceKind {
    OutputDeviceKind(transportType: transportType, dataSource: dataSource, terminalType: terminalType)
}

/// Der Fall, der das Ganze ausgeloest hat: USB-C-EarPods kommen ueber USB,
/// melden am Ausgabestream aber Kopfhoerer.
@Test func usbDeviceWithHeadphoneTerminalCountsAsHeadphones() {
    #expect(kind(kAudioDeviceTransportTypeUSB, terminalType: kAudioStreamTerminalTypeHeadphones) == .headphones)
}

@Test func rawUSBHeadphoneAndHeadsetTerminalsCountAsHeadphones() {
    #expect(kind(kAudioDeviceTransportTypeUSB, terminalType: 0x0302) == .headphones)
    #expect(kind(kAudioDeviceTransportTypeUSB, terminalType: 0x0402) == .headphones)
}

@Test func usbDeviceWithSpeakerTerminalCountsAsSpeakers() {
    #expect(kind(kAudioDeviceTransportTypeUSB, terminalType: kAudioStreamTerminalTypeSpeaker) == .speakers)
    #expect(kind(kAudioDeviceTransportTypeUSB, terminalType: 0x0301) == .speakers)
    #expect(kind(kAudioDeviceTransportTypeUSB) == .speakers)
}

@Test func bluetoothDeviceCountsAsHeadphones() {
    #expect(kind(kAudioDeviceTransportTypeBluetooth) == .headphones)
    #expect(kind(kAudioDeviceTransportTypeBluetoothLE) == .headphones)
}

/// Die Klinkenbuchse ist kein eigenes Geraet: der eingebaute Ausgang meldet
/// nur eine andere Datenquelle.
@Test func builtInOutputWithHeadphoneJackCountsAsHeadphones() {
    let headphones: UInt32 = 0x6864_706E   // 'hdpn'
    #expect(kind(kAudioDeviceTransportTypeBuiltIn, dataSource: headphones) == .headphones)
}

@Test func builtInSpeakersCountAsSpeakers() {
    let speakers: UInt32 = 0x6973_7063   // 'ispk'
    #expect(kind(kAudioDeviceTransportTypeBuiltIn, dataSource: speakers, terminalType: 0x0301) == .speakers)
    #expect(kind(kAudioDeviceTransportTypeBuiltIn) == .speakers)
}

/// Im Zweifel Lautsprecher: ein zu leiser Alarm im Raum wird verpasst, und
/// genau das soll alarmooh verhindern.
@Test func otherTransportsCountAsSpeakers() {
    #expect(kind(kAudioDeviceTransportTypeHDMI, terminalType: 0) == .speakers)
    #expect(kind(kAudioDeviceTransportTypeDisplayPort) == .speakers)
    #expect(kind(kAudioDeviceTransportTypeAirPlay) == .speakers)
    #expect(kind(kAudioDeviceTransportTypeUnknown) == .speakers)
}

@Test func minimumVolumeFollowsDeviceKind() {
    var settings = Settings()
    settings.minimumVolume = 0.8
    settings.headphoneMinimumVolume = 0.3

    #expect(OutputDeviceKind.speakers.minimumVolume(in: settings) == 0.8)
    #expect(OutputDeviceKind.headphones.minimumVolume(in: settings) == 0.3)
}
