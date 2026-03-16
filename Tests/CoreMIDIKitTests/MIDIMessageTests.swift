import Testing
@testable import CoreMIDIKit

@Suite("MIDIMessage")
struct MIDIMessageTests {

    @Test("Parse Note On")
    func noteOn() {
        let msg = MIDIMessage.parse(status: 0x90, data1: 60, data2: 100)
        if case .noteOn(let ch, let note, let vel) = msg {
            #expect(ch == 0)
            #expect(note == 60)
            #expect(vel == 100)
        } else {
            Issue.record("Expected noteOn")
        }
    }

    @Test("Parse Note On with velocity 0 becomes Note Off")
    func noteOnVelocityZero() {
        let msg = MIDIMessage.parse(status: 0x90, data1: 60, data2: 0)
        if case .noteOff = msg {
            // correct
        } else {
            Issue.record("Expected noteOff for velocity-0 noteOn")
        }
    }

    @Test("Parse Control Change")
    func controlChange() {
        let msg = MIDIMessage.parse(status: 0xB3, data1: 7, data2: 127)
        if case .controlChange(let ch, let cc, let val) = msg {
            #expect(ch == 3)
            #expect(cc == 7)
            #expect(val == 127)
        } else {
            Issue.record("Expected controlChange")
        }
    }

    @Test("Parse Program Change")
    func programChange() {
        let msg = MIDIMessage.parse(status: 0xC5, data1: 42, data2: 0)
        if case .programChange(let ch, let pgm) = msg {
            #expect(ch == 5)
            #expect(pgm == 42)
        } else {
            Issue.record("Expected programChange")
        }
    }
}
