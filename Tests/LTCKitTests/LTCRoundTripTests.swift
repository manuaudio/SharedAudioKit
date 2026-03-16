import Testing
@testable import LTCKit
import TimecodeKit

@Suite("LTC Round-Trip")
struct LTCRoundTripTests {

    @Test("Encode then decode produces matching timecode")
    func encodeDecodeRoundTrip() {
        let tc = Timecode(hours: 1, minutes: 23, seconds: 45, frames: 6)
        let rate = FrameRate.fps30
        let sampleRate = 48000.0
        let totalSamples = Int(sampleRate * 2) // 2 seconds

        let audio = LTCEncoder.encode(
            timecodes: [(tc, 0)],
            rate: rate,
            sampleRate: sampleRate,
            totalSamples: totalSamples
        )

        let decoder = LTCDecoder(sampleRate: sampleRate)
        let frames = decoder.decode(samples: audio, sampleOffset: 0)

        #expect(!frames.isEmpty, "Decoder should find at least one frame")
        if let first = frames.first {
            #expect(first.timecode == tc)
            #expect(!first.dropFrame)
        }
    }

    @Test("Drop-frame flag round-trips correctly")
    func dropFrameRoundTrip() {
        let tc = Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2) // Valid DF timecode
        let sampleRate = 48000.0
        let totalSamples = Int(sampleRate * 2)

        let audio = LTCEncoder.encode(
            timecodes: [(tc, 0)],
            rate: .fps2997df,
            sampleRate: sampleRate,
            totalSamples: totalSamples
        )

        let decoder = LTCDecoder(sampleRate: sampleRate)
        let frames = decoder.decode(samples: audio, sampleOffset: 0)

        #expect(!frames.isEmpty)
        if let first = frames.first {
            #expect(first.dropFrame == true)
            #expect(first.quantizedRate == .fps2997df)
        }
    }

    @Test("Frame rate quantization")
    func quantization() {
        #expect(LTCDecoder.quantizeFrameRate(23.976, dropFrame: false) == 23.976)
        #expect(LTCDecoder.quantizeFrameRate(23.98, dropFrame: false) == 23.976)
        #expect(LTCDecoder.quantizeFrameRate(24.0, dropFrame: false) == 24.0)
        #expect(LTCDecoder.quantizeFrameRate(25.0, dropFrame: false) == 25.0)
        #expect(LTCDecoder.quantizeFrameRate(29.97, dropFrame: true) == 29.97)
        #expect(LTCDecoder.quantizeFrameRate(30.0, dropFrame: false) == 30.0)
    }
}
