import AVFoundation
import Foundation

/// Erzeugt den mitgelieferten Ersatzton. Bewusst selbst erzeugt statt als
/// Audiodatei im Repository: fremdes Tonmaterial gehoert nicht ins Git.
public enum ToneGenerator {
    /// Zwei absteigende Toene, wie ein schlichtes Stationssignal.
    public static func writeFallbackTone(to url: URL) throws {
        let sampleRate = 44_100.0
        let noteDuration = 0.55
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
                // Exponentiell abklingende Huellkurve, damit es nach Glocke klingt.
                let envelope = exp(-3.0 * t / noteDuration)
                samples[frame] = Float(sin(2 * .pi * frequency * t) * envelope * 0.9)
            }
            try file.write(from: buffer)
        }
    }

    enum ToneError: Error {
        case formatUnavailable
        case bufferUnavailable
    }
}
