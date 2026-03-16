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
}
