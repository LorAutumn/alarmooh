import AVFoundation
import Foundation

/// Erzeugt den mitgelieferten Ersatzton. Bewusst selbst erzeugt statt als
/// Audiodatei im Repository: fremdes Tonmaterial gehoert nicht ins Git.
public enum ToneGenerator {
    /// Zwei absteigende Toene, wie ein schlichtes Stationssignal.
    ///
    /// WICHTIG - nicht in eine Tuerklingel zurueckbauen: Die Huellkurve haelt
    /// bewusst fast die gesamte Note auf voller Amplitude. Das hier ist ein
    /// Wecker, kein Gong. Eine abklingende (exponentielle) Huellkurve klingt
    /// huebscher, verbringt aber den groessten Teil der Note nahe Null und geht
    /// im Gespraech oder unter Kopfhoerern schlicht unter. Der Nutzer will den
    /// Alarm sicher bemerken, darum: Sustain statt Decay.
    ///
    /// Attack und Release sind nur kurze lineare Rampen. Sie muessen bleiben:
    /// ein harter Ein-/Aussatz erzeugt einen hoerbaren Klick und eine
    /// Gleichspannungsstufe am Notenuebergang und an der Schleifennaht.
    public static func writeFallbackTone(to url: URL) throws {
        let sampleRate = 44_100.0
        let noteDuration = 0.55
        let attack = 0.015  // Sekunden, klickfreier Einsatz
        let release = 0.025  // Sekunden, klickfreies Ende und saubere Schleifennaht
        let amplitude = 0.95
        let frequencies: [Double] = [987.77, 659.25]  // H5, E5

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw ToneError.formatUnavailable
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        for frequency in frequencies {
            let frames = AVAudioFrameCount(sampleRate * noteDuration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = buffer.floatChannelData?[0]
            else { throw ToneError.bufferUnavailable }
            buffer.frameLength = frames

            for frame in 0..<Int(frames) {
                let t = Double(frame) / sampleRate
                // Sustain-Huellkurve: kurz rein, lange voll, kurz raus.
                let envelope: Double
                if t < attack {
                    envelope = t / attack
                } else if t > noteDuration - release {
                    envelope = max(0, (noteDuration - t) / release)
                } else {
                    envelope = 1.0
                }
                samples[frame] = Float(sin(2 * .pi * frequency * t) * envelope * amplitude)
            }
            try file.write(from: buffer)
        }
    }

    enum ToneError: Error {
        case formatUnavailable
        case bufferUnavailable
    }
}
