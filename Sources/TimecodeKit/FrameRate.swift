//
//  FrameRate.swift
//  TimecodeKit
//
//  Standard SMPTE timecode frame rates.
//

import Foundation

/// Standard SMPTE timecode frame rates.
public enum FrameRate: String, Codable, CaseIterable, Sendable {
    case fps23976    // 23.976 (film pulldown)
    case fps24
    case fps25
    case fps2997df   // 29.97 drop-frame (NTSC broadcast)
    case fps30       // 30.000 non-drop

    /// Integer frames-per-second used for frame math.
    /// For 23.976, math uses 24 fps. For 29.97 DF, math uses 30 fps with drop-frame corrections.
    public var fps: Int {
        switch self {
        case .fps23976: return 24
        case .fps24: return 24
        case .fps25: return 25
        case .fps2997df: return 30
        case .fps30: return 30
        }
    }

    /// Whether this rate uses drop-frame timecode.
    public var isDropFrame: Bool { self == .fps2997df }

    /// Real-world rate in frames per second.
    public var realRate: Double {
        switch self {
        case .fps23976: return 23.976
        case .fps24: return 24.0
        case .fps25: return 25.0
        case .fps2997df: return 29.97
        case .fps30: return 30.0
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .fps23976: return "23.976"
        case .fps24: return "24"
        case .fps25: return "25"
        case .fps2997df: return "29.97 DF"
        case .fps30: return "30"
        }
    }

    /// MTC rate code bits (2-bit value for quarter-frame message type 7).
    /// Note: MTC has no 23.976 rate code; 23.976 uses the 24fps code (0).
    public var mtcRateBits: UInt8 {
        switch self {
        case .fps23976: return 0
        case .fps24: return 0
        case .fps25: return 1
        case .fps2997df: return 2
        case .fps30: return 3
        }
    }

    /// Failable initializer that returns nil for unrecognized fps values.
    /// Use this when processing external input (e.g. LTC measured rates)
    /// where silent defaulting to 30fps would hide errors.
    public init?(validatingFPS fps: Int, dropFrame: Bool) {
        if dropFrame && (fps == 30 || fps == 29) {
            self = .fps2997df
            return
        }
        switch fps {
        case 24: self = .fps24
        case 25: self = .fps25
        case 30: self = .fps30
        default: return nil
        }
    }

    /// Construct from the legacy (fps: Int, dropFrame: Bool) pair.
    public init(fps: Int, dropFrame: Bool) {
        if dropFrame && (fps == 30 || fps == 29) {
            self = .fps2997df
            return
        }
        switch fps {
        case 24: self = .fps24
        case 25: self = .fps25
        default: self = .fps30
        }
    }

    /// Construct from a raw measured frame rate (e.g., from LTC timing).
    /// Uses the drop-frame flag as the authoritative indicator for 29.97 vs 30.
    public init(measuredRate: Double, dropFrame: Bool) {
        if measuredRate < 23.99 {
            self = .fps23976
        } else if measuredRate < 24.5 {
            self = .fps24
        } else if measuredRate < 27.0 {
            self = .fps25
        } else {
            self = dropFrame ? .fps2997df : .fps30
        }
    }
}
