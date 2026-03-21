import Testing
@testable import TriggerKit
import TimecodeKit

@Suite("InternalClockTimecodeSource")
struct InternalClockTimecodeSourceTests {

    @Test("Initial state is inactive")
    func initialState() {
        let source = InternalClockTimecodeSource()

        #expect(source.sourceID == "internal")
        #expect(source.priority == 1)
        #expect(!source.isActive)
        #expect(source.currentTimecode == .zero)
        #expect(source.currentRate == .fps30)
    }

    @Test("markInactive sets isActive to false")
    func markInactive() {
        let source = InternalClockTimecodeSource()
        source.markInactive()
        #expect(!source.isActive)
    }

    @Test("Custom sourceID and priority")
    func customInit() {
        let source = InternalClockTimecodeSource(sourceID: "preview", priority: 5)
        #expect(source.sourceID == "preview")
        #expect(source.priority == 5)
    }

    @Test("bind(to:) captures timecode updates from clock")
    @MainActor
    func bindUpdatesTimecode() {
        let clock = InternalClock()
        let source = InternalClockTimecodeSource()

        // Set up a previous callback to verify chaining
        var previousCallbackFired = false
        clock.onTimecode = { _ in previousCallbackFired = true }

        source.bind(to: clock)

        // Simulate the clock firing onTimecode
        let tc = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4)
        clock.onTimecode?(tc)

        #expect(source.currentTimecode == tc)
        #expect(source.isActive)
        #expect(previousCallbackFired, "Previous callback should be chained")
    }

    @Test("bind(to:) reads clock rate")
    @MainActor
    func bindReadsRate() {
        let clock = InternalClock()
        let source = InternalClockTimecodeSource()

        // Start and immediately stop to set the rate without a running timer
        clock.start(from: .zero, rate: .fps25)
        clock.stop()

        source.bind(to: clock)
        #expect(source.currentRate == .fps25)
    }
}
