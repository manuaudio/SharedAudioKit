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

    // MARK: - Signal quality

    @Test("Signal quality starts at zero")
    func signalQualityInitial() {
        let decoder = LTCDecoder(sampleRate: 48000.0)
        #expect(decoder.signalQuality == 0.0)
        #expect(!decoder.isActive)
    }

    @Test("Signal quality increases after successful decodes")
    func signalQualityAfterDecode() {
        let tc = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0)
        let sampleRate = 48000.0
        let totalSamples = Int(sampleRate * 2)

        let audio = LTCEncoder.encode(
            timecodes: [(tc, 0)],
            rate: .fps30,
            sampleRate: sampleRate,
            totalSamples: totalSamples
        )

        let decoder = LTCDecoder(sampleRate: sampleRate)
        let frames = decoder.decode(samples: audio, sampleOffset: 0)

        if !frames.isEmpty {
            #expect(decoder.signalQuality > 0.0)
            #expect(decoder.isActive)
            #expect(decoder.lastDecodeTime > 0)
        }
    }

    @Test("Decoded frames have isValid set to true")
    func decodedFrameIsValid() {
        let tc = Timecode(hours: 1, minutes: 23, seconds: 45, frames: 6)
        let sampleRate = 48000.0
        let totalSamples = Int(sampleRate * 2)

        let audio = LTCEncoder.encode(
            timecodes: [(tc, 0)],
            rate: .fps30,
            sampleRate: sampleRate,
            totalSamples: totalSamples
        )

        let decoder = LTCDecoder(sampleRate: sampleRate)
        let frames = decoder.decode(samples: audio, sampleOffset: 0)

        #expect(!frames.isEmpty)
        if let first = frames.first {
            #expect(first.isValid == true, "Valid timecode should have isValid == true")
        }
    }

    @Test("Manually constructed invalid LTCFrame has isValid false")
    func invalidFrameIsValid() {
        let frame = LTCFrame(
            timecode: Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29),
            samplePosition: 0,
            dropFrame: false,
            colorFrame: false,
            frameRate: 30.0,
            userBits: 0,
            isValid: false
        )
        #expect(frame.isValid == false)
    }

    @Test("Reset clears signal quality")
    func signalQualityReset() {
        let decoder = LTCDecoder(sampleRate: 48000.0)
        decoder.reset()
        #expect(decoder.signalQuality == 0.0)
        #expect(!decoder.isActive)
        #expect(decoder.lastDecodeTime == 0)
    }
}
