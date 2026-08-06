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
