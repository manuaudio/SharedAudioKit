//
//  LockQuality.swift
//  TimecodeKit
//
//  Signal quality assessment for timecode lock (MTC, LTC, or any sync source).
//

import Foundation

/// Signal quality level for a timecode sync source.
public enum LockQuality: String, Sendable {
    case good = "Good"
    case weak = "Weak"
    case unstable = "Unstable"

    /// Suggested UI color name for this quality level.
    public var color: String {
        switch self {
        case .good: return "green"
        case .weak: return "yellow"
        case .unstable: return "orange"
        }
    }
}
