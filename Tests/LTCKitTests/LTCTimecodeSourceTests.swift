import Testing
@testable import LTCKit
import TimecodeKit

@Suite("LTCTimecodeSource")
struct LTCTimecodeSourceTests {

    @Test("Initial state is inactive")
    func initialState() {
        let decoder = LTCDecoder(sampleRate: 48000.0)
        let source = LTCTimecodeSource(decoder: decoder)

        #expect(source.sourceID == "ltc")
        #expect(source.priority == 10)
        #expect(!source.isActive)
        #expect(source.currentTimecode == .zero)
        #expect(source.currentRate == .fps30)
    }

    @Test("update() caches latest frame values")
    func updateCachesValues() {
        let decoder = LTCDecoder(sampleRate: 48000.0)
        let source = LTCTimecodeSource(decoder: decoder)

        let tc = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4)
        let frame = LTCFrame(
            timecode: tc,
            samplePosition: 0,
            dropFrame: true,
            colorFrame: false,
            frameRate: 29.97,
            userBits: 0
        )

        source.update(frames: [frame])

        #expect(source.currentTimecode == tc)
        #expect(source.currentRate == .fps2997df)
    }

    @Test("update() with empty array does not change state")
    func updateEmptyNoChange() {
        let decoder = LTCDecoder(sampleRate: 48000.0)
        let source = LTCTimecodeSource(decoder: decoder)

        source.update(frames: [])
        #expect(source.currentTimecode == .zero)
    }

    @Test("Custom sourceID and priority")
    func customInit() {
        let decoder = LTCDecoder(sampleRate: 48000.0)
        let source = LTCTimecodeSource(decoder: decoder, sourceID: "ltc-main", priority: 50)

        #expect(source.sourceID == "ltc-main")
        #expect(source.priority == 50)
    }
}
