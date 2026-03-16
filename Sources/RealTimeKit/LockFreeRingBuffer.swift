//
//  LockFreeRingBuffer.swift
//  RealTimeKit
//
//  Lock-free single-producer single-consumer ring buffer for real-time audio.
//  Uses atomic operations for thread-safe access without locks.
//
//  THREAD SAFETY: Real-time safe (no locks, no allocations)
//  USE CASE: Transfer audio between real-time IOProc and disk I/O threads.
//

import Foundation

/// Lock-free single-producer single-consumer ring buffer.
///
/// Uses atomic operations to coordinate between:
/// - Producer: Real-time audio IOProc (writes to buffer)
/// - Consumer: Disk I/O thread (reads from buffer)
public final class LockFreeRingBuffer {

    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let writeIndex: UnsafeMutablePointer<Int32>
    private let readIndex: UnsafeMutablePointer<Int32>

    /// Create a lock-free ring buffer with specified capacity.
    /// - Parameter capacity: Maximum number of audio frames (samples) to store.
    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0.0, count: capacity)
        self.writeIndex = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self.writeIndex.initialize(to: 0)
        self.readIndex = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self.readIndex.initialize(to: 0)
    }

    deinit {
        buffer.deallocate()
        writeIndex.deallocate()
        readIndex.deallocate()
    }

    // MARK: - Public API

    /// Number of frames available for writing.
    public func availableWrite() -> Int {
        let write = Int(writeIndex.pointee)
        let read = Int(readIndex.pointee)
        let available: Int
        if write >= read {
            available = capacity - (write - read)
        } else {
            available = read - write
        }
        return max(0, available - 1)
    }

    /// Number of frames available for reading.
    public func availableRead() -> Int {
        let write = Int(writeIndex.pointee)
        let read = Int(readIndex.pointee)
        if write >= read {
            return write - read
        } else {
            return capacity - read + write
        }
    }

    /// Write audio samples to the ring buffer.
    /// - Returns: Number of frames actually written (may be less if buffer is full).
    @discardableResult
    public func write(_ data: UnsafePointer<Float>, frameCount: Int) -> Int {
        let write = Int(writeIndex.pointee)
        let read = Int(readIndex.pointee)
        let available: Int
        if write >= read {
            available = capacity - (write - read) - 1
        } else {
            available = read - write - 1
        }
        let count = min(frameCount, available)
        guard count > 0 else { return 0 }

        let firstChunk = min(count, capacity - write)
        if firstChunk > 0 {
            memcpy(buffer.advanced(by: write), data, firstChunk * MemoryLayout<Float>.size)
        }
        let secondChunk = count - firstChunk
        if secondChunk > 0 {
            memcpy(buffer, data.advanced(by: firstChunk), secondChunk * MemoryLayout<Float>.size)
        }

        OSMemoryBarrier()
        writeIndex.pointee = Int32((write + count) % capacity)
        return count
    }

    /// Read audio samples from the ring buffer.
    /// - Returns: Number of frames actually read (may be less if buffer is empty).
    @discardableResult
    public func read(_ output: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let write = Int(writeIndex.pointee)
        let read = Int(readIndex.pointee)
        let available: Int
        if write >= read {
            available = write - read
        } else {
            available = capacity - read + write
        }
        let count = min(frameCount, available)
        guard count > 0 else { return 0 }

        let firstChunk = min(count, capacity - read)
        if firstChunk > 0 {
            memcpy(output, buffer.advanced(by: read), firstChunk * MemoryLayout<Float>.size)
        }
        let secondChunk = count - firstChunk
        if secondChunk > 0 {
            memcpy(output.advanced(by: firstChunk), buffer, secondChunk * MemoryLayout<Float>.size)
        }

        OSMemoryBarrier()
        readIndex.pointee = Int32((read + count) % capacity)
        return count
    }

    /// Fill the ring buffer with silence.
    /// - Returns: Number of frames actually written.
    @discardableResult
    public func writeSilence(frameCount: Int) -> Int {
        let write = Int(writeIndex.pointee)
        let read = Int(readIndex.pointee)
        let available: Int
        if write >= read {
            available = capacity - (write - read) - 1
        } else {
            available = read - write - 1
        }
        let count = min(frameCount, available)
        guard count > 0 else { return 0 }

        let firstChunk = min(count, capacity - write)
        if firstChunk > 0 {
            memset(buffer.advanced(by: write), 0, firstChunk * MemoryLayout<Float>.stride)
        }
        let secondChunk = count - firstChunk
        if secondChunk > 0 {
            memset(buffer, 0, secondChunk * MemoryLayout<Float>.stride)
        }
        let currentWrite = (write + count) % capacity

        OSMemoryBarrier()
        writeIndex.pointee = Int32(currentWrite)
        return count
    }

    /// Reset the ring buffer to empty state.
    /// WARNING: Only call when no other threads are accessing the buffer.
    public func reset() {
        writeIndex.pointee = 0
        readIndex.pointee = 0
        buffer.initialize(repeating: 0.0, count: capacity)
    }

    /// Current fill level (0.0 = empty, 1.0 = full).
    public var fillLevel: Float {
        Float(availableRead()) / Float(capacity)
    }

    /// Whether the buffer is empty.
    public var isEmpty: Bool { availableRead() == 0 }

    /// Whether the buffer is full.
    public var isFull: Bool { availableWrite() == 0 }

    // MARK: - Statistics

    /// Buffer statistics snapshot for monitoring/debugging.
    public struct Statistics {
        public let capacity: Int
        public let availableRead: Int
        public let availableWrite: Int
        public let fillLevel: Float
        public let isEmpty: Bool
        public let isFull: Bool
    }

    /// Get current statistics snapshot.
    public var statistics: Statistics {
        Statistics(
            capacity: capacity,
            availableRead: availableRead(),
            availableWrite: availableWrite(),
            fillLevel: fillLevel,
            isEmpty: isEmpty,
            isFull: isFull
        )
    }
}
