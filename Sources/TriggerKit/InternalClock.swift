//
//  InternalClock.swift
//  TriggerKit
//
//  Simulated timecode clock for freewheel / manual playback mode.
//  Generates frame-accurate timecode from a start point using wall-clock timing.
//
//  IMPORTANT: All access to this class must be from the main thread.
//  The Timer callback and all property reads are main-thread only.
//

import Foundation
import TimecodeKit

/// Simulated timecode generator for playback/preview mode.
///
/// Starts from a given timecode and advances in real time at the specified rate.
/// Does not depend on any external timecode source.
///
/// - Important: Use this class only from the main thread.
@MainActor
public final class InternalClock {

    /// The current simulated timecode.
    public private(set) var timecode: Timecode = .zero

    /// Whether the clock is running.
    public private(set) var isRunning: Bool = false

    /// The frame rate for this clock.
    public private(set) var rate: FrameRate = .fps30

    private var startTC: Timecode = .zero
    private var startDate: Date = .now
    private var timer: Timer?

    /// Called on each frame advance with the new timecode.
    public var onTimecode: ((Timecode) -> Void)?

    public init() {}

    deinit { stop() }

    /// Start the clock from a given timecode.
    public func start(from startTC: Timecode, rate: FrameRate) {
        self.startTC = startTC
        self.rate = rate
        self.startDate = Date()
        self.timecode = startTC
        self.isRunning = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / rate.realRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                let elapsed = Date().timeIntervalSince(self.startDate)
                let totalFrames = self.startTC.toFrames(rate: self.rate) + Int(elapsed * Double(self.rate.fps))
                self.timecode = Timecode.fromFrames(totalFrames, rate: self.rate)
                self.onTimecode?(self.timecode)
            }
        }
    }

    /// Stop the clock.
    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}
