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
/// Dieser Test schaut in die Samples: der Alarm muss laut bleiben, nicht nur
/// abspielbar sein. Er faellt, sobald jemand die Sustain-Huellkurve wieder
/// gegen ein Abklingen tauscht (das alte Abklingen kam auf RMS 0.26).
@Test func fallbackToneIsLoudAndClickFree() throws {
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

    #expect(peak >= 0.9)
    #expect(rms >= 0.5)
    #expect(abs(first) < 0.01)
    #expect(abs(last) < 0.01)
}
