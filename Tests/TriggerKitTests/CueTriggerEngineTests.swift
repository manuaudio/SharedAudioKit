import Testing
@testable import TriggerKit
import TimecodeKit

struct TestCue: TriggerCue {
    let cueID: UUID
    let startTimecode: Timecode
    let endTimecode: Timecode?
    let displayName: String
    let midiProgram: Int
    let isEnabled: Bool

    init(name: String, start: Timecode, end: Timecode? = nil, program: Int = 1, enabled: Bool = true) {
        self.cueID = UUID()
        self.startTimecode = start
        self.endTimecode = end
        self.displayName = name
        self.midiProgram = program
        self.isEnabled = enabled
    }
}

@Suite("CueTriggerEngine")
struct CueTriggerEngineTests {

    @Test("Triggers when timecode enters cue range")
    func basicTrigger() {
        let engine = CueTriggerEngine()
        let cues: [any TriggerCue] = [
            TestCue(name: "Cue 1", start: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0), program: 1),
            TestCue(name: "Cue 2", start: Timecode(hours: 0, minutes: 0, seconds: 20, frames: 0), program: 2),
        ]
        engine.loadCues(cues, rate: .fps30)

        // Before any cue
        let e1 = engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 5, frames: 0))
        #expect(e1 == nil)

        // Enter cue 1
        let e2 = engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0))
        #expect(e2 != nil)
        #expect(e2?.displayName == "Cue 1")
        #expect(e2?.midiProgram == 1)

        // Stay in cue 1 — no re-trigger
        let e3 = engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 15, frames: 0))
        #expect(e3 == nil)

        // Enter cue 2
        let e4 = engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 20, frames: 0))
        #expect(e4 != nil)
        #expect(e4?.displayName == "Cue 2")
    }

    @Test("Disabled cues are skipped")
    func disabledCues() {
        let engine = CueTriggerEngine()
        let cues: [any TriggerCue] = [
            TestCue(name: "Disabled", start: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0), enabled: false),
            TestCue(name: "Enabled", start: Timecode(hours: 0, minutes: 0, seconds: 20, frames: 0)),
        ]
        engine.loadCues(cues, rate: .fps30)

        let e1 = engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0))
        #expect(e1 == nil)

        let e2 = engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 20, frames: 0))
        #expect(e2 != nil)
        #expect(e2?.displayName == "Enabled")
    }

    @Test("Reset clears trigger state")
    func resetState() {
        let engine = CueTriggerEngine()
        let cues: [any TriggerCue] = [
            TestCue(name: "Cue 1", start: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0)),
        ]
        engine.loadCues(cues, rate: .fps30)
        engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0))

        engine.reset()
        #expect(engine.ranges.isEmpty)
    }
}
