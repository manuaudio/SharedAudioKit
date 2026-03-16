import Testing
@testable import MTCKit
import TimecodeKit

@Suite("MTCDecoder")
struct MTCDecoderTests {

    @Test("Full-frame SysEx decode")
    func fullFrameSysEx() {
        let decoder = MTCDecoder()
        var received: (Timecode, FrameRate)?
        decoder.onFullFrame = { tc, rate in received = (tc, rate) }

        // F0 7F 7F 01 01 hr mn sc fr F7
        // Rate code 3 (30fps) in upper 2 bits of hour byte: 0x60 | 1 = 0x61
        let sysEx: [UInt8] = [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x61, 0x17, 0x2D, 0x0A, 0xF7]
        for byte in sysEx { decoder.processByte(byte) }

        #expect(received != nil)
        if let (tc, rate) = received {
            #expect(tc.hours == 1)
            #expect(tc.minutes == 23)
            #expect(tc.seconds == 45)
            #expect(tc.frames == 10)
            #expect(rate == .fps30)
        }
    }

    @Test("Quarter-frame decode with 2-frame compensation")
    func quarterFrameDecode() {
        let decoder = MTCDecoder()
        var received: (Timecode, FrameRate)?
        decoder.onTimecode = { tc, rate in received = (tc, rate) }

        // Encode timecode 01:23:45:12 at 30fps (rate code 3)
        // QF encodes the value + 2 frames = 01:23:45:14
        let h = 1, m = 23, s = 45, f = 14
        let rateCode: UInt8 = 3 // 30fps

        let qfMessages: [UInt8] = [
            0xF1, UInt8(0x00 | (f & 0x0F)),           // QF0: frame low
            0xF1, UInt8(0x10 | ((f >> 4) & 0x01)),     // QF1: frame high
            0xF1, UInt8(0x20 | (s & 0x0F)),            // QF2: seconds low
            0xF1, UInt8(0x30 | ((s >> 4) & 0x03)),     // QF3: seconds high
            0xF1, UInt8(0x40 | (m & 0x0F)),            // QF4: minutes low
            0xF1, UInt8(0x50 | ((m >> 4) & 0x03)),     // QF5: minutes high
            0xF1, UInt8(0x60 | (h & 0x0F)),            // QF6: hours low
            0xF1, UInt8(0x70 | ((h >> 4) & 0x01) | (rateCode << 1)), // QF7: hours high + rate
        ]

        for byte in qfMessages { decoder.processByte(byte) }

        #expect(received != nil)
        if let (tc, rate) = received {
            // Corrected = 14 - 2 = 12
            #expect(tc.frames == 12)
            #expect(tc.hours == 1)
            #expect(tc.minutes == 23)
            #expect(tc.seconds == 45)
            #expect(rate == .fps30)
        }
    }

    @Test("Full-frame suppresses next QF decode")
    func fullFrameSuppressesQF() {
        let decoder = MTCDecoder()
        var qfCount = 0
        decoder.onTimecode = { _, _ in qfCount += 1 }

        // Send full-frame first
        let sysEx: [UInt8] = [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x60, 0x00, 0x00, 0x00, 0xF7]
        for byte in sysEx { decoder.processByte(byte) }

        // Send 8 QF messages (should be suppressed)
        for i in 0..<8 {
            decoder.processByte(0xF1)
            decoder.processByte(UInt8(i << 4))
        }

        #expect(qfCount == 0, "First QF cycle after full-frame should be suppressed")
    }

    @Test("Reset clears state")
    func resetClearsState() {
        let decoder = MTCDecoder()
        let sysEx: [UInt8] = [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x61, 0x17, 0x2D, 0x0A, 0xF7]
        for byte in sysEx { decoder.processByte(byte) }
        #expect(decoder.timecode.hours == 1)

        decoder.reset()
        #expect(decoder.timecode == .zero)
        #expect(decoder.frameRate == .fps30)
        #expect(decoder.lastDecodeTime == 0)
    }

    // MARK: - SysEx buffer cap

    @Test("SysEx buffer capped at 256 bytes")
    func sysExBufferCap() {
        let decoder = MTCDecoder()
        var fullFrameReceived = false
        decoder.onFullFrame = { _, _ in fullFrameReceived = true }

        // Start SysEx
        decoder.processByte(0xF0)
        // Feed 300 junk bytes (exceeds 256 cap)
        for _ in 0..<300 {
            decoder.processByte(0x42)
        }
        // End SysEx — should have been discarded due to cap
        decoder.processByte(0xF7)

        #expect(!fullFrameReceived, "Oversized SysEx should be discarded")
    }

    @Test("Valid SysEx still works after capped one")
    func sysExWorksAfterCap() {
        let decoder = MTCDecoder()
        var received = false
        decoder.onFullFrame = { _, _ in received = true }

        // Oversized SysEx (discarded)
        decoder.processByte(0xF0)
        for _ in 0..<300 { decoder.processByte(0x42) }
        decoder.processByte(0xF7)

        // Valid full-frame SysEx
        let sysEx: [UInt8] = [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x61, 0x17, 0x2D, 0x0A, 0xF7]
        for byte in sysEx { decoder.processByte(byte) }

        #expect(received, "Valid SysEx after discarded one should still work")
    }

    // MARK: - Liveness tracking

    @Test("isActive reflects recent decode")
    func livenessTracking() {
        let decoder = MTCDecoder()
        #expect(!decoder.isActive, "Should be inactive before any decode")

        let sysEx: [UInt8] = [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x61, 0x17, 0x2D, 0x0A, 0xF7]
        for byte in sysEx { decoder.processByte(byte) }

        #expect(decoder.isActive, "Should be active right after decode")
        #expect(decoder.lastDecodeTime > 0)
    }
}
