//
//  CueTriggerEngine.swift
//  TriggerKit
//
//  Generic edge-triggered timecode cue engine.
//  Given a current timecode and a list of cues, determines which cues to fire.
//  Handles hysteresis, forward-crossing detection, and pre-computed ranges.
//

import Foundation
import TimecodeKit

/// Pre-computed cue range for fast lookup.
public struct CueRange: Sendable, Codable {
    public let startFrames: Int
    public let endFrames: Int
    public let cueID: UUID
    public let displayName: String
    public let midiProgram: Int
    public let cueIndex: Int

    public init(startFrames: Int, endFrames: Int, cueID: UUID,
                displayName: String, midiProgram: Int, cueIndex: Int) {
        self.startFrames = startFrames
        self.endFrames = endFrames
        self.cueID = cueID
        self.displayName = displayName
        self.midiProgram = midiProgram
        self.cueIndex = cueIndex
    }
}

/// Trigger event returned when a cue fires.
public struct TriggerEvent: Sendable {
    public let cueID: UUID
    public let displayName: String
    public let midiProgram: Int
    public let cueIndex: Int
    public let rangeIndex: Int
}

/// Edge-triggered timecode cue engine.
///
/// Call `loadCues()` with your cue list, then call `evaluate()` at your
/// polling rate (typically 30Hz). The engine returns trigger events for
/// cues whose range the timecode has entered.
///
/// Thread-safe: `loadCues()` and `evaluate()` can be called from different threads.
public final class CueTriggerEngine {

    /// Called when a cue is triggered.
    public var onCueTriggered: ((TriggerEvent) -> Void)?

    private let queue = DispatchQueue(label: "com.manuaudio.cuetrigger")
    private var cueRanges: [CueRange] = []
    private var rate: FrameRate = .fps30
    private var lastTriggeredCueID: UUID?
    private var lastTriggerFrame: Int = -100
    private let hysteresisFrames = 2

    /// Max frame sentinel.
    private var maxFrames: Int { 24 * 3600 * rate.fps - 1 }

    public init() {}

    // MARK: - Load Cues

    /// Load cues and pre-compute ranges for fast lookup.
    public func loadCues(_ cues: [any TriggerCue], rate: FrameRate) {
        var newRanges: [CueRange] = []

        var eligible: [(index: Int, cue: any TriggerCue, startFrames: Int)] = []
        for (i, cue) in cues.enumerated() {
            guard cue.isEnabled else { continue }
            eligible.append((i, cue, cue.startTimecode.toFrames(rate: rate)))
        }

        eligible.sort { $0.startFrames < $1.startFrames }

        let maxF = 24 * 3600 * rate.fps - 1
        for (j, entry) in eligible.enumerated() {
            let endFrames: Int
            if let endTC = entry.cue.endTimecode {
                endFrames = endTC.toFrames(rate: rate)
            } else if j + 1 < eligible.count {
                endFrames = eligible[j + 1].startFrames
            } else {
                endFrames = maxF
            }
            guard endFrames > entry.startFrames else { continue }

            newRanges.append(CueRange(
                startFrames: entry.startFrames,
                endFrames: endFrames,
                cueID: entry.cue.cueID,
                displayName: entry.cue.displayName,
                midiProgram: entry.cue.midiProgram,
                cueIndex: entry.index
            ))
        }

        queue.sync {
            self.rate = rate
            self.lastTriggeredCueID = nil
            self.lastTriggerFrame = -100
            self.cueRanges = newRanges
        }
    }

    /// Load pre-computed ranges directly.
    public func loadRanges(_ ranges: [CueRange], rate: FrameRate) {
        queue.sync {
            self.rate = rate
            self.lastTriggeredCueID = nil
            self.lastTriggerFrame = -100
            self.cueRanges = ranges
        }
    }

    // MARK: - Evaluate

    /// Evaluate the current timecode against loaded cues.
    /// Returns the trigger event if a new cue was entered, nil otherwise.
    @discardableResult
    public func evaluate(currentTimecode: Timecode) -> TriggerEvent? {
        queue.sync {
            let liveFrames = currentTimecode.toFrames(rate: rate)

            // Binary search: find the last range whose startFrames <= liveFrames
            var lo = 0, hi = cueRanges.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if cueRanges[mid].startFrames <= liveFrames {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            // lo - 1 is the candidate range (if any)
            let candidateIdx = lo - 1

            if candidateIdx >= 0 {
                let range = cueRanges[candidateIdx]
                if liveFrames >= range.startFrames && liveFrames < range.endFrames {
                    if lastTriggeredCueID != range.cueID {
                        let frameDelta = abs(liveFrames - lastTriggerFrame)
                        if frameDelta < hysteresisFrames && lastTriggeredCueID != nil {
                            return nil
                        }

                        lastTriggeredCueID = range.cueID
                        lastTriggerFrame = liveFrames

                        let event = TriggerEvent(
                            cueID: range.cueID,
                            displayName: range.displayName,
                            midiProgram: range.midiProgram,
                            cueIndex: range.cueIndex,
                            rangeIndex: candidateIdx
                        )
                        onCueTriggered?(event)
                        return event
                    }
                    return nil
                }
            }

            if lastTriggeredCueID != nil {
                lastTriggeredCueID = nil
            }
            return nil
        }
    }

    /// Reset trigger state (clears last-triggered tracking).
    public func reset() {
        queue.sync {
            lastTriggeredCueID = nil
            lastTriggerFrame = -100
            cueRanges.removeAll()
        }
    }

    /// The current loaded ranges (read-only).
    public var ranges: [CueRange] {
        queue.sync { cueRanges }
    }

    /// The cue range the timecode is currently inside, if any.
    public var currentCue: CueRange? {
        queue.sync {
            guard let id = lastTriggeredCueID else { return nil }
            return cueRanges.first(where: { $0.cueID == id })
        }
    }

    /// Number of the next cue after the given range index, or nil.
    public func nextCue(afterRangeIndex idx: Int) -> CueRange? {
        queue.sync {
            idx + 1 < cueRanges.count ? cueRanges[idx + 1] : nil
        }
    }
}
