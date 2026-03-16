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

    // MARK: - Bytes round-trip

    @Test("NoteOn bytes round-trip")
    func noteOnBytes() {
        let msg = MIDIMessage.noteOn(channel: 3, note: 60, velocity: 100)
        #expect(msg.bytes == [0x93, 60, 100])
        let parsed = MIDIMessage.parse(status: msg.bytes[0], data1: msg.bytes[1], data2: msg.bytes[2])
        if case .noteOn(let ch, let n, let v) = parsed {
            #expect(ch == 3)
            #expect(n == 60)
            #expect(v == 100)
        } else {
            Issue.record("Expected noteOn after round-trip")
        }
    }

    @Test("NoteOff bytes round-trip")
    func noteOffBytes() {
        let msg = MIDIMessage.noteOff(channel: 0, note: 48, velocity: 64)
        #expect(msg.bytes == [0x80, 48, 64])
    }

    @Test("CC bytes round-trip")
    func ccBytes() {
        let msg = MIDIMessage.controlChange(channel: 5, controller: 7, value: 127)
        #expect(msg.bytes == [0xB5, 7, 127])
    }

    @Test("Program Change bytes")
    func programChangeBytes() {
        let msg = MIDIMessage.programChange(channel: 0, program: 42)
        #expect(msg.bytes == [0xC0, 42])
    }

    @Test("Quarter Frame bytes")
    func quarterFrameBytes() {
        let msg = MIDIMessage.quarterFrame(data: 0x30)
        #expect(msg.bytes == [0xF1, 0x30])
    }

    @Test("SysEx bytes include F0/F7 framing")
    func sysExBytes() {
        let msg = MIDIMessage.sysEx(data: [0x7F, 0x01, 0x02])
        #expect(msg.bytes == [0xF0, 0x7F, 0x01, 0x02, 0xF7])
    }
}
