import Testing
@testable import MTCKit
import TimecodeKit

@Suite("MTCTimecodeSource")
struct MTCTimecodeSourceTests {

    @Test("Initial state is inactive with defaults")
    func initialState() {
        let decoder = MTCDecoder()
        let source = MTCTimecodeSource(decoder: decoder)

        #expect(source.sourceID == "mtc")
        #expect(source.priority == 20)
        #expect(!source.isActive)
        #expect(source.currentTimecode == .zero)
        #expect(source.currentRate == .fps30)
    }

    @Test("Reflects decoder state after full-frame SysEx")
    func reflectsDecoderState() {
        let decoder = MTCDecoder()
        let source = MTCTimecodeSource(decoder: decoder)

        // Feed a full-frame MTC SysEx: F0 7F 7F 01 01 hr mn sc fr F7
        // Rate code 3 (30fps), hours=1, minutes=2, seconds=3, frames=4
        let hr: UInt8 = (3 << 5) | 1  // rate=30fps, hours=1
        let bytes: [UInt8] = [0xF0, 0x7F, 0x7F, 0x01, 0x01, hr, 2, 3, 4, 0xF7]
        decoder.processBytes(bytes)

        #expect(source.currentTimecode == Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4))
        #expect(source.currentRate == .fps30)
        #expect(source.isActive)
    }

    @Test("Custom sourceID and priority")
    func customInit() {
        let decoder = MTCDecoder()
        let source = MTCTimecodeSource(decoder: decoder, sourceID: "mtc-backup", priority: 5)

        #expect(source.sourceID == "mtc-backup")
        #expect(source.priority == 5)
    }
}
