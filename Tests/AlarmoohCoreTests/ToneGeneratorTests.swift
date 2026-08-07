import AVFoundation
import Foundation
import Testing
@testable import AlarmoohCore

@Test func generatesPlayableWavFile() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("alarmooh-tone-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }

    try ToneGenerator.writeFallbackTone(to: url)

    let file = try AVAudioFile(forReading: url)
    let seconds = Double(file.length) / file.fileFormat.sampleRate
    #expect(seconds > 1.0)
    #expect(seconds < 4.0)
}

/// Der Dauertest oben wuerde auch bei einer voellig stillen Datei gruen sein.
/// Dieser Test schaut in die Samples: der Ersatzton ist absichtlich freundlich,
/// aber er darf nicht zur Stille verkommen - eine Regression, die den Alarm
/// leise dreht, muss rot werden.
///
/// Dazu die Absicherung gegen das Knacken, das der Nutzer tatsaechlich gehoert
/// hat: Ohne die Release-Rampe je Note bricht der Ton am Notenende mit
/// Restamplitude ab. Sichtbar wird das in der zweiten Differenz des Signals -
/// ohne Rampe erreichte deren Maximum das 15-fache des Mittelwerts, mit Rampe
/// bleibt es beim 9-fachen. Der Generator ist deterministisch, das flackert nicht.
@Test func fallbackToneIsAudibleAndClickFree() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("alarmooh-tone-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }

    try ToneGenerator.writeFallbackTone(to: url)

    let file = try AVAudioFile(forReading: url)
    // read(into:) fuellt den Puffer nicht zwingend in einem Rutsch, darum
    // stueckweise lesen, bis die Datei durch ist.
    let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)
    )
    var samples: [Float] = []
    while file.framePosition < file.length {
        try file.read(into: buffer)
        guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
    #expect(samples.count == Int(file.length))
    let first = try #require(samples.first)
    let last = try #require(samples.last)

    var peak: Float = 0
    var sumOfSquares = 0.0
    for sample in samples {
        peak = max(peak, abs(sample))
        sumOfSquares += Double(sample) * Double(sample)
    }
    let rms = (sumOfSquares / Double(samples.count)).squareRoot()

    #expect(peak >= 0.8)  // normalisiert wird auf 0,85
    #expect(rms >= 0.12)  // deutlich ueber Stille, deutlich unter der alten Sirene
    #expect(abs(first) < 0.01)
    #expect(abs(last) < 0.01)

    // Zweite Differenz: ein Knick im Signal sticht hier als Spitze heraus.
    var maxSecondDifference = 0.0
    var sumOfSecondDifferences = 0.0
    for i in 1..<(samples.count - 1) {
        let value = abs(Double(samples[i + 1]) - 2 * Double(samples[i]) + Double(samples[i - 1]))
        maxSecondDifference = max(maxSecondDifference, value)
        sumOfSecondDifferences += value
    }
    let meanSecondDifference = sumOfSecondDifferences / Double(samples.count - 2)
    #expect(meanSecondDifference > 0)
    #expect(maxSecondDifference <= 12 * meanSecondDifference)
}
