//
//  TimecodeRouter.swift
//  TimecodeKit
//
//  Selects the best active timecode source from multiple inputs.
//  TC Trigger uses this to see both MTC and LTC simultaneously with priority.
//

import Foundation

/// Selects the best active timecode source from multiple inputs.
///
/// Usage:
/// ```swift
/// let router = TimecodeRouter()
/// router.addSource(ltcSource)   // priority 10
/// router.addSource(mtcSource)   // priority 20 (preferred)
/// router.addSource(clockSource) // priority 1  (fallback)
///
/// // Poll at 30Hz from your display timer:
/// router.poll()
/// ```
public final class TimecodeRouter {

    /// All registered sources.
    public private(set) var sources: [any TimecodeSource] = []

    /// Called when the active timecode changes. Parameters: timecode, rate, sourceID.
    public var onTimecode: ((Timecode, FrameRate, String) -> Void)?

    /// Called when the active source changes (e.g., MTC goes dead, falls back to LTC).
    public var onSourceChanged: ((String?) -> Void)?

    private var lastActiveSourceID: String?
    private var lastTimecode: Timecode = .zero

    public init() {}

    // MARK: - Source Management

    /// Register a timecode source.
    public func addSource(_ source: any TimecodeSource) {
        sources.append(source)
    }

    /// Remove a source by its ID.
    public func removeSource(id: String) {
        sources.removeAll { $0.sourceID == id }
        if lastActiveSourceID == id {
            lastActiveSourceID = nil
        }
    }

    /// Remove all registered sources.
    public func removeAllSources() {
        sources.removeAll()
        lastActiveSourceID = nil
    }

    // MARK: - Polling

    /// Returns the highest-priority active source, or nil if none are active.
    public var activeSource: (any TimecodeSource)? {
        sources
            .filter(\.isActive)
            .max(by: { $0.priority < $1.priority })
    }

    /// Poll all sources and fire callbacks. Call at your display/evaluation rate (e.g., 30Hz).
    public func poll() {
        guard let source = activeSource else {
            if lastActiveSourceID != nil {
                lastActiveSourceID = nil
                onSourceChanged?(nil)
            }
            return
        }

        // Notify if active source changed
        if source.sourceID != lastActiveSourceID {
            lastActiveSourceID = source.sourceID
            onSourceChanged?(source.sourceID)
        }

        let tc = source.currentTimecode
        let rate = source.currentRate

        // Only fire if timecode actually changed
        if tc != lastTimecode {
            lastTimecode = tc
            onTimecode?(tc, rate, source.sourceID)
        }
    }
}
