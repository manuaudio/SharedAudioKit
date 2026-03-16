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

    // MARK: - currentCue

    @Test("currentCue returns active cue after trigger")
    func currentCue() {
        let engine = CueTriggerEngine()
        let cues: [any TriggerCue] = [
            TestCue(name: "Cue 1", start: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0)),
        ]
        engine.loadCues(cues, rate: .fps30)

        #expect(engine.currentCue == nil, "No cue before evaluation")

        engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0))
        #expect(engine.currentCue != nil)
        #expect(engine.currentCue?.displayName == "Cue 1")
    }

    @Test("currentCue clears when leaving all ranges")
    func currentCueClears() {
        let engine = CueTriggerEngine()
        let cues: [any TriggerCue] = [
            TestCue(name: "Cue 1",
                    start: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0),
                    end: Timecode(hours: 0, minutes: 0, seconds: 15, frames: 0)),
        ]
        engine.loadCues(cues, rate: .fps30)
        engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0))
        #expect(engine.currentCue != nil)

        // Move past end
        engine.evaluate(currentTimecode: Timecode(hours: 0, minutes: 0, seconds: 16, frames: 0))
        #expect(engine.currentCue == nil)
    }

    // MARK: - CueRange Codable

    @Test("CueRange round-trips through JSON")
    func cueRangeCodable() throws {
        let range = CueRange(
            startFrames: 300,
            endFrames: 600,
            cueID: UUID(),
            displayName: "Test Cue",
            midiProgram: 5,
            cueIndex: 2
        )

        let data = try JSONEncoder().encode(range)
        let decoded = try JSONDecoder().decode(CueRange.self, from: data)

        #expect(decoded.startFrames == range.startFrames)
        #expect(decoded.endFrames == range.endFrames)
        #expect(decoded.cueID == range.cueID)
        #expect(decoded.displayName == range.displayName)
        #expect(decoded.midiProgram == range.midiProgram)
        #expect(decoded.cueIndex == range.cueIndex)
    }
}
