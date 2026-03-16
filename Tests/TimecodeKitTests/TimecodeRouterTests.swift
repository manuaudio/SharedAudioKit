import Testing
@testable import TimecodeKit

/// Mock timecode source for testing.
final class MockTimecodeSource: TimecodeSource {
    let sourceID: String
    var currentTimecode: Timecode
    var currentRate: FrameRate
    var isActive: Bool
    var priority: Int

    init(id: String, timecode: Timecode = .zero, rate: FrameRate = .fps30,
         active: Bool = false, priority: Int = 0) {
        self.sourceID = id
        self.currentTimecode = timecode
        self.currentRate = rate
        self.isActive = active
        self.priority = priority
    }
}

@Suite("TimecodeRouter")
struct TimecodeRouterTests {

    @Test("Picks highest-priority active source")
    func highestPriority() {
        let router = TimecodeRouter()
        let ltc = MockTimecodeSource(id: "ltc", active: true, priority: 10)
        let mtc = MockTimecodeSource(id: "mtc", active: true, priority: 20)
        let clock = MockTimecodeSource(id: "clock", active: true, priority: 1)

        router.addSource(ltc)
        router.addSource(mtc)
        router.addSource(clock)

        #expect(router.activeSource?.sourceID == "mtc")
    }

    @Test("Falls back when preferred source goes inactive")
    func fallback() {
        let router = TimecodeRouter()
        let ltc = MockTimecodeSource(id: "ltc", active: true, priority: 10)
        let mtc = MockTimecodeSource(id: "mtc", active: false, priority: 20)

        router.addSource(ltc)
        router.addSource(mtc)

        #expect(router.activeSource?.sourceID == "ltc")
    }

    @Test("Returns nil when no sources are active")
    func noActive() {
        let router = TimecodeRouter()
        let src = MockTimecodeSource(id: "ltc", active: false, priority: 10)
        router.addSource(src)

        #expect(router.activeSource == nil)
    }

    @Test("Poll fires onTimecode callback")
    func pollCallback() {
        let router = TimecodeRouter()
        let src = MockTimecodeSource(
            id: "mtc",
            timecode: Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0),
            active: true,
            priority: 10
        )
        router.addSource(src)

        var received: (Timecode, FrameRate, String)?
        router.onTimecode = { tc, rate, id in received = (tc, rate, id) }
        router.poll()

        #expect(received != nil)
        #expect(received?.0.hours == 1)
        #expect(received?.2 == "mtc")
    }

    @Test("Poll fires onSourceChanged when source switches")
    func sourceChanged() {
        let router = TimecodeRouter()
        router.sourceChangeDebounce = 0.0 // disable debounce for this test
        let ltc = MockTimecodeSource(id: "ltc", timecode: Timecode(hours: 0, minutes: 0, seconds: 1, frames: 0), active: true, priority: 10)
        let mtc = MockTimecodeSource(id: "mtc", timecode: Timecode(hours: 0, minutes: 0, seconds: 2, frames: 0), active: true, priority: 20)
        router.addSource(ltc)
        router.addSource(mtc)

        var changedTo: [String?] = []
        router.onSourceChanged = { changedTo.append($0) }

        router.poll() // first poll picks mtc
        mtc.isActive = false
        router.poll() // falls back to ltc

        #expect(changedTo == ["mtc", "ltc"])
    }

    @Test("Remove source by ID")
    func removeSource() {
        let router = TimecodeRouter()
        let src = MockTimecodeSource(id: "ltc", active: true, priority: 10)
        router.addSource(src)
        #expect(router.sources.count == 1)

        router.removeSource(id: "ltc")
        #expect(router.sources.isEmpty)
    }

    @Test("Remove all sources")
    func removeAll() {
        let router = TimecodeRouter()
        router.addSource(MockTimecodeSource(id: "a", active: true, priority: 1))
        router.addSource(MockTimecodeSource(id: "b", active: true, priority: 2))
        router.removeAllSources()
        #expect(router.sources.isEmpty)
        #expect(router.activeSource == nil)
    }

    @Test("Source change debounce throttles rapid switches")
    func sourceChangeDebounce() {
        let router = TimecodeRouter()
        router.sourceChangeDebounce = 0.0 // disable for existing tests

        let ltc = MockTimecodeSource(id: "ltc", timecode: Timecode(hours: 0, minutes: 0, seconds: 1, frames: 0), active: true, priority: 10)
        let mtc = MockTimecodeSource(id: "mtc", timecode: Timecode(hours: 0, minutes: 0, seconds: 2, frames: 0), active: true, priority: 20)
        router.addSource(ltc)
        router.addSource(mtc)

        // With debounce = 1.0, rapid switching should be throttled
        router.sourceChangeDebounce = 1.0
        var changedTo: [String?] = []
        router.onSourceChanged = { changedTo.append($0) }

        router.poll() // first poll picks mtc — fires because no previous
        mtc.isActive = false
        router.poll() // wants ltc, but debounce blocks
        mtc.isActive = true
        router.poll() // mtc again, no change notification

        #expect(changedTo.count == 1, "Debounce should throttle rapid source changes")
        #expect(changedTo.first == "mtc")
    }

    @Test("No duplicate timecode callbacks when TC unchanged")
    func noDuplicateCallbacks() {
        let router = TimecodeRouter()
        let src = MockTimecodeSource(
            id: "mtc",
            timecode: Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0),
            active: true,
            priority: 10
        )
        router.addSource(src)

        var callCount = 0
        router.onTimecode = { _, _, _ in callCount += 1 }
        router.poll()
        router.poll()

        #expect(callCount == 1, "Should not fire again if timecode hasn't changed")
    }
}
