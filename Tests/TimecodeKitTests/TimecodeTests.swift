import Testing
@testable import TimecodeKit

@Suite("Timecode")
struct TimecodeTests {

    // MARK: - toFrames / fromFrames round-trip

    @Test("Round-trip at 30 NDF")
    func roundTrip30() {
        let tc = Timecode(hours: 1, minutes: 23, seconds: 45, frames: 6)
        let frames = tc.toFrames(rate: .fps30)
        let back = Timecode.fromFrames(frames, rate: .fps30)
        #expect(back == tc)
    }

    @Test("Round-trip at 24 fps")
    func roundTrip24() {
        let tc = Timecode(hours: 0, minutes: 59, seconds: 59, frames: 23)
        let frames = tc.toFrames(rate: .fps24)
        let back = Timecode.fromFrames(frames, rate: .fps24)
        #expect(back == tc)
    }

    @Test("Round-trip at 25 fps")
    func roundTrip25() {
        let tc = Timecode(hours: 23, minutes: 59, seconds: 59, frames: 24)
        let frames = tc.toFrames(rate: .fps25)
        let back = Timecode.fromFrames(frames, rate: .fps25)
        #expect(back == tc)
    }

    // MARK: - Drop-frame edge cases

    @Test("Drop-frame minute boundary: 00:01:00:00 skips to :02")
    func dropFrameMinute1() {
        // At 29.97 DF, frames 00:00:59:29 + 1 = 00:01:00:02 (frames 0,1 skipped)
        let tc = Timecode(hours: 0, minutes: 0, seconds: 59, frames: 29)
        let next = tc.adding(frames: 1, rate: .fps2997df)
        #expect(next == Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2))
    }

    @Test("Drop-frame 10-minute boundary: 00:10:00:00 does NOT skip")
    func dropFrameMinute10() {
        let tc = Timecode(hours: 0, minutes: 9, seconds: 59, frames: 29)
        let next = tc.adding(frames: 1, rate: .fps2997df)
        #expect(next == Timecode(hours: 0, minutes: 10, seconds: 0, frames: 0))
    }

    @Test("Drop-frame round-trip for all minutes in first hour")
    func dropFrameFullHourRoundTrip() {
        for min in 0..<60 {
            let tc = Timecode(hours: 0, minutes: min, seconds: 30, frames: 15)
            let frames = tc.toFrames(rate: .fps2997df)
            let back = Timecode.fromFrames(frames, rate: .fps2997df)
            #expect(back == tc, "Failed at minute \(min)")
        }
    }

    // MARK: - adding() across midnight

    @Test("Adding across midnight wraps correctly")
    func addingAcrossMidnight() {
        let tc = Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29)
        let next = tc.adding(frames: 1, rate: .fps30)
        #expect(next == Timecode(hours: 24, minutes: 0, seconds: 0, frames: 0))
    }

    // MARK: - Parse

    @Test("Parse valid timecode")
    func parseValid() {
        let tc = Timecode.parse("01:23:45:06")
        #expect(tc == Timecode(hours: 1, minutes: 23, seconds: 45, frames: 6))
    }

    @Test("Parse invalid strings return nil")
    func parseInvalid() {
        #expect(Timecode.parse("not a timecode") == nil)
        #expect(Timecode.parse("25:00:00:00") == nil)  // hours > 23
        #expect(Timecode.parse("00:60:00:00") == nil)  // minutes > 59
    }

    // MARK: - distance()

    @Test("Distance is symmetric")
    func distanceSymmetric() {
        let a = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0)
        let b = Timecode(hours: 1, minutes: 0, seconds: 1, frames: 0)
        #expect(a.distance(to: b, rate: .fps30) == 30)
        #expect(b.distance(to: a, rate: .fps30) == -30)
    }

    // MARK: - FrameRate

    @Test("FrameRate legacy constructor")
    func frameRateLegacy() {
        #expect(FrameRate(fps: 30, dropFrame: true) == .fps2997df)
        #expect(FrameRate(fps: 30, dropFrame: false) == .fps30)
        #expect(FrameRate(fps: 24, dropFrame: false) == .fps24)
        #expect(FrameRate(fps: 25, dropFrame: false) == .fps25)
    }

    @Test("FrameRate measured rate constructor")
    func frameRateMeasured() {
        #expect(FrameRate(measuredRate: 23.976, dropFrame: false) == .fps23976)
        #expect(FrameRate(measuredRate: 23.98, dropFrame: false) == .fps23976)
        #expect(FrameRate(measuredRate: 24.0, dropFrame: false) == .fps24)
        #expect(FrameRate(measuredRate: 25.0, dropFrame: false) == .fps25)
        #expect(FrameRate(measuredRate: 29.97, dropFrame: true) == .fps2997df)
        #expect(FrameRate(measuredRate: 30.0, dropFrame: false) == .fps30)
    }

    @Test("FrameRate properties")
    func frameRateProperties() {
        #expect(FrameRate.fps2997df.isDropFrame == true)
        #expect(FrameRate.fps30.isDropFrame == false)
        #expect(FrameRate.fps2997df.fps == 30)
        #expect(FrameRate.fps2997df.realRate == 29.97)
    }

    // MARK: - displayString round-trip

    @Test("displayString → parse round-trip")
    func displayStringParse() {
        let tc = Timecode(hours: 12, minutes: 34, seconds: 56, frames: 28)
        let parsed = Timecode.parse(tc.displayString)
        #expect(parsed == tc)
    }

    // MARK: - Legacy API

    @Test("Legacy toFrames/fromFrames still works")
    func legacyAPI() {
        let tc = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0)
        let frames = tc.toFrames(fps: 30, dropFrame: false)
        #expect(frames == 108000)
        let back = Timecode.fromFrames(frames, fps: 30, dropFrame: false)
        #expect(back == tc)
    }
}
