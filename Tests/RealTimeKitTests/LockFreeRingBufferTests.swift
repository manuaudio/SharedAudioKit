import Testing
@testable import RealTimeKit

@Suite("LockFreeRingBuffer")
struct LockFreeRingBufferTests {

    @Test("Write and read round-trip")
    func writeReadRoundTrip() {
        let buffer = LockFreeRingBuffer(capacity: 1024)
        let input: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
        let written = input.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, frameCount: input.count)
        }
        #expect(written == 5)

        var output = [Float](repeating: 0, count: 5)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(ptr.baseAddress!, frameCount: 5)
        }
        #expect(read == 5)
        #expect(output == input)
    }

    @Test("Empty buffer returns zero reads")
    func emptyRead() {
        let buffer = LockFreeRingBuffer(capacity: 64)
        var output = [Float](repeating: 0, count: 10)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(ptr.baseAddress!, frameCount: 10)
        }
        #expect(read == 0)
        #expect(buffer.isEmpty)
    }

    @Test("Fill level tracks correctly")
    func fillLevel() {
        let buffer = LockFreeRingBuffer(capacity: 100)
        let data = [Float](repeating: 1.0, count: 50)
        data.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, frameCount: 50)
        }
        // ~50% fill (minus 1 for gap)
        #expect(buffer.fillLevel > 0.45)
        #expect(!buffer.isEmpty)
        #expect(!buffer.isFull)
    }

    @Test("Wrap-around works correctly")
    func wrapAround() {
        let buffer = LockFreeRingBuffer(capacity: 8)
        // Write 5 samples, read 5, write 5 more (forces wrap)
        let data1: [Float] = [1, 2, 3, 4, 5]
        data1.withUnsafeBufferPointer { ptr in buffer.write(ptr.baseAddress!, frameCount: 5) }
        var discard = [Float](repeating: 0, count: 5)
        discard.withUnsafeMutableBufferPointer { ptr in buffer.read(ptr.baseAddress!, frameCount: 5) }

        let data2: [Float] = [6, 7, 8, 9, 10]
        let written = data2.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, frameCount: 5)
        }
        #expect(written == 5)

        var output = [Float](repeating: 0, count: 5)
        buffer.read(&output, frameCount: 5)
        #expect(output == data2)
    }

    @Test("Reset clears buffer")
    func reset() {
        let buffer = LockFreeRingBuffer(capacity: 64)
        let data = [Float](repeating: 1.0, count: 32)
        data.withUnsafeBufferPointer { ptr in buffer.write(ptr.baseAddress!, frameCount: 32) }
        #expect(!buffer.isEmpty)
        buffer.reset()
        #expect(buffer.isEmpty)
    }

    // MARK: - Array convenience API

    @Test("Array write and read round-trip")
    func arrayRoundTrip() {
        let buffer = LockFreeRingBuffer(capacity: 1024)
        let input: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
        let written = buffer.write(input)
        #expect(written == 5)

        let output = buffer.read(frameCount: 5)
        #expect(output == input)
    }

    @Test("Array read returns shorter array when less data available")
    func arrayReadPartial() {
        let buffer = LockFreeRingBuffer(capacity: 64)
        buffer.write([10.0, 20.0, 30.0])

        let output = buffer.read(frameCount: 10)
        #expect(output.count == 3)
        #expect(output == [10.0, 20.0, 30.0])
    }

    @Test("Array read on empty buffer returns empty array")
    func arrayReadEmpty() {
        let buffer = LockFreeRingBuffer(capacity: 64)
        let output = buffer.read(frameCount: 5)
        #expect(output.isEmpty)
    }

    @Test("Array write respects capacity")
    func arrayWriteCapacity() {
        let buffer = LockFreeRingBuffer(capacity: 8)
        let data = [Float](repeating: 1.0, count: 20)
        let written = buffer.write(data)
        #expect(written < 20, "Should not write more than capacity allows")
        #expect(written == 7) // capacity - 1 for gap
    }
}
