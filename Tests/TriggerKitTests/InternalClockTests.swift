import Testing
@testable import TriggerKit
import TimecodeKit

@Suite("InternalClock")
struct InternalClockTests {

    @Test("computeTimecode uses realRate, not integer fps")
    func computeTimecodeUsesRealRate() {
        let startTC = Timecode.zero
        let elapsed = 3600.0 // 1 hour

        // At 29.97 DF, expected frames = Int(3600.0 * 29.97) = 107892
        let result = InternalClock.computeTimecode(elapsed: elapsed, startTC: startTC, rate: .fps2997df)
        let resultFrames = result.toFrames(rate: .fps2997df)

        let expectedFrames = Int(3600.0 * 29.97)
        #expect(resultFrames == expectedFrames,
                "Expected \(expectedFrames) frames at 29.97DF, got \(resultFrames)")

        // Bug would produce 3600 * 30 = 108000 frames — 108 frames too many
        let buggyFrames = 3600 * 30
        #expect(resultFrames != buggyFrames,
                "Result should NOT equal buggy integer fps calculation (\(buggyFrames))")
    }

    @Test("computeTimecode at 30 NDF matches integer fps")
    func computeTimecodeAt30NDF() {
        let startTC = Timecode.zero
        let elapsed = 3600.0

        let result = InternalClock.computeTimecode(elapsed: elapsed, startTC: startTC, rate: .fps30)
        let resultFrames = result.toFrames(rate: .fps30)

        // At 30 NDF, realRate == 30.0, so both paths agree
        #expect(resultFrames == 108000)
    }

    @Test("computeTimecode preserves start offset")
    func computeTimecodeWithStartOffset() {
        let startTC = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0)
        let elapsed = 10.0

        let result = InternalClock.computeTimecode(elapsed: elapsed, startTC: startTC, rate: .fps30)
        let expected = Timecode(hours: 1, minutes: 0, seconds: 10, frames: 0)
        #expect(result == expected)
    }

    @Test("computeTimecode at 25fps")
    func computeTimecodeAt25() {
        let startTC = Timecode.zero
        let elapsed = 60.0

        let result = InternalClock.computeTimecode(elapsed: elapsed, startTC: startTC, rate: .fps25)
        let resultFrames = result.toFrames(rate: .fps25)
        #expect(resultFrames == 1500) // 60 * 25
    }
}
