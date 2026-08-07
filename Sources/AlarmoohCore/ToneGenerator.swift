import AVFoundation
import Foundation

/// Erzeugt den mitgelieferten Ersatzton. Bewusst selbst erzeugt statt als
/// Audiodatei im Repository: fremdes Tonmaterial gehoert nicht ins Git.
public enum ToneGenerator {
    /// Fuenf aufsteigende Toene einer Pentatonik (E5, G5, A5, C6, D6), die sich
    /// ueberlappen und zusammen 2,4 Sekunden ergeben.
    ///
    /// WICHTIG - nicht wieder in eine Sirene zurueckbauen: Der Ton laeuft in
    /// Endlosschleife, bis der Nutzer ihn abstellt. Die Dringlichkeit liefert
    /// also die WIEDERHOLUNG, nicht die Klangfarbe. Die frueheren zwei
    /// gehaltenen Toene auf fast voller Amplitude haben ein angenehmes Glockchen
    /// gegen ein Alarmsignal getauscht - das war der falsche Tausch.
    ///
    /// Jede Note ist ein Sinus plus ein leiser zweiter Teilton, beide mit
    /// exponentiell abklingender Huellkurve. Alle Noten werden in EINEN Puffer
    /// summiert (sie ueberlappen), der Puffer wird am Ende auf Spitze 0,85
    /// normalisiert.
    public static func writeFallbackTone(to url: URL) throws {
        let sampleRate = 44_100.0
        let totalLength = 2.40  // Sekunden, Gesamtlaenge der Datei
        let attack = 0.006  // Sekunden, klickfreier Einsatz
        let release = 0.09  // Sekunden, siehe unten - muss bleiben
        let peak = 0.85

        // (Vielfaches der Grundfrequenz, Anteil, Abklingrate)
        let partials: [(multiple: Double, amount: Double, decay: Double)] = [
            (1.0, 1.0, 2.2),
            (2.0, 0.18, 4.0),
        ]
        // (Frequenz, Startzeitpunkt, Dauer) - die letzte Note laeuft bis kurz
        // vors Dateiende aus, damit die Schleife nahtlos weitergeht.
        let notes: [(frequency: Double, start: Double, duration: Double)] = [
            (659.25, 0.00, 0.90),  // E5
            (783.99, 0.18, 0.90),  // G5
            (880.00, 0.36, 0.90),  // A5
            (1046.50, 0.54, 1.10),  // C6
            (1174.66, 0.72, 1.60),  // D6
        ]

        let frameCount = Int(sampleRate * totalLength)
        var mix = [Double](repeating: 0, count: frameCount)

        for note in notes {
            let startFrame = Int(note.start * sampleRate)
            let noteFrames = Int(note.duration * sampleRate)
            for offset in 0..<noteFrames {
                let index = startFrame + offset
                guard index < frameCount else { break }
                let t = Double(offset) / sampleRate

                let attackGain = min(1.0, t / attack)
                // NICHT wegkuerzen: Ohne diese Ausblendung bricht jede Note
                // mitten im Ausklingen bei rund 11 % Amplitude ab, und das
                // knackt hoerbar. Gemessen an der zweiten Differenz des Signals:
                // ohne Rampe Ausschlaege vom 15-, 10- und 13-fachen des
                // Mittelwerts, und zwar exakt bei 0,900 s, 1,080 s und 1,640 s -
                // den Notenenden. Mit Rampe bleiben davon 6 bis 9 Mittelwerte
                // uebrig, also nur noch die natuerliche Kruemmung der hohen Toene.
                let releaseGain = min(1.0, max(0.0, (note.duration - t) / release))

                var sample = 0.0
                for partial in partials {
                    let envelope = exp(-partial.decay * t / note.duration)
                    sample += sin(2 * .pi * note.frequency * partial.multiple * t)
                        * partial.amount * envelope
                }
                mix[index] += sample * attackGain * releaseGain
            }
        }

        // Erst die Summe normalisieren: Die Ueberlappungen addieren sich, ein
        // Pegel pro Note waere nicht vorhersagbar.
        let maxAbs = mix.lazy.map(abs).max() ?? 0
        let scale = maxAbs > 0 ? peak / maxAbs : 1

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw ToneError.formatUnavailable
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)
        ), let samples = buffer.floatChannelData?[0] else {
            throw ToneError.bufferUnavailable
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for frame in 0..<frameCount {
            samples[frame] = Float(mix[frame] * scale)
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    enum ToneError: Error {
        case formatUnavailable
        case bufferUnavailable
    }
}
