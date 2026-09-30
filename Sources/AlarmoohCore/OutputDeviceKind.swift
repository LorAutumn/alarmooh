import CoreAudio

/// Ob der Alarm im Raum oder im Ohr landet. Davon haengt ab, welche Lautstaerke
/// der Alarm bekommt: 80 % aus dem Notebooklautsprecher sind ein Wecker, 80 %
/// in Kopfhoerern tun weh.
public enum OutputDeviceKind: Equatable, Sendable {
    case speakers
    case headphones

    /// Datenquelle des eingebauten Ausgangs, wenn etwas in der Klinkenbuchse
    /// steckt ('hdpn'). CoreAudio exportiert dafuer keine Konstante.
    static let headphoneJackDataSource: UInt32 = 0x6864_706E

    /// Terminaltypen, die USB-Audio-Geraete roh weiterreichen, statt sie auf
    /// eine CoreAudio-Konstante abzubilden (USB Audio Terminal Types 1.0):
    /// 0x0302 Kopfhoerer, 0x0402 Headset. Die eingebauten Lautsprecher melden
    /// auf demselben Weg 0x0301.
    static let usbHeadphoneTerminalTypes: Set<UInt32> = [0x0302, 0x0402]

    /// Einordnung aus drei Merkmalen, das verlaesslichste zuerst:
    ///
    /// 1. Der Terminaltyp des Ausgabestreams. Er beschreibt, was am Ende der
    ///    Leitung haengt, unabhaengig vom Transportweg — USB-C-EarPods melden
    ///    hier `kAudioStreamTerminalTypeHeadphones`, obwohl sie ueber USB
    ///    kommen, wo auch Monitorboxen und Audiointerfaces haengen.
    /// 2. Die Datenquelle des eingebauten Ausgangs: die Klinkenbuchse ist kein
    ///    eigenes Geraet, sie schaltet nur die Quelle um.
    /// 3. Bluetooth. CoreAudio unterscheidet Bluetooth-Kopfhoerer nicht von
    ///    Bluetooth-Lautsprechern, am Mac sind es aber fast immer AirPods oder
    ///    ein Headset.
    ///
    /// Alles andere gilt als Lautsprecher. Die Richtung im Zweifel ist Absicht:
    /// ein zu leiser Alarm im Raum wird verpasst, und genau das soll alarmooh
    /// verhindern.
    public init(transportType: UInt32, dataSource: UInt32?, terminalType: UInt32?) {
        if let terminalType,
           terminalType == kAudioStreamTerminalTypeHeadphones
            || Self.usbHeadphoneTerminalTypes.contains(terminalType) {
            self = .headphones
            return
        }
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            self = .headphones
        case kAudioDeviceTransportTypeBuiltIn where dataSource == Self.headphoneJackDataSource:
            self = .headphones
        default:
            self = .speakers
        }
    }

    /// Die Lautstaerke, die fuer den Alarm eingestellt werden soll, oder nil,
    /// wenn die aktuelle schon passt.
    ///
    /// Lautsprecher bekommen eine Untergrenze: war es leiser, wird angehoben,
    /// war es lauter, bleibt es dabei — ein Alarm im Raum darf nicht untergehen.
    /// Kopfhoerer bekommen genau den eingestellten Wert, auch nach unten: sonst
    /// kaeme der Alarm bei laut gestellter Musik mit derselben Lautstaerke ins
    /// Ohr, und der Regler waere kein Schutz.
    public func alarmVolume(current: Float, in settings: Settings) -> Float? {
        switch self {
        case .speakers:
            current < settings.minimumVolume ? settings.minimumVolume : nil
        case .headphones:
            current != settings.headphoneVolume ? settings.headphoneVolume : nil
        }
    }
}
