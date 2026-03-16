//
//  LTCFrame.swift
//  LTCKit
//
//  A single decoded LTC frame with its position in the audio stream.
//

import Foundation
import TimecodeKit

/// A single decoded LTC frame with its position in the audio file.
public struct LTCFrame: Sendable {
    /// The decoded timecode value.
    public let timecode: Timecode
    /// Sample offset of the frame start in the audio stream.
    public let samplePosition: UInt64
    /// Whether the drop-frame flag was set in this frame.
    public let dropFrame: Bool
    /// Whether the color-frame flag was set.
    public let colorFrame: Bool
    /// Raw estimated frame rate from bit cell timing.
    public let frameRate: Double
    /// 32 user bits packed into a UInt32.
    public let userBits: UInt32
    /// Whether the decoded fields had valid SMPTE ranges before clamping.
    public let isValid: Bool

    /// The quantized FrameRate from the raw timing + drop-frame flag.
    public var quantizedRate: FrameRate {
        FrameRate(measuredRate: frameRate, dropFrame: dropFrame)
    }

    public init(timecode: Timecode, samplePosition: UInt64, dropFrame: Bool,
                colorFrame: Bool, frameRate: Double, userBits: UInt32, isValid: Bool = true) {
        self.timecode = timecode
        self.samplePosition = samplePosition
        self.dropFrame = dropFrame
        self.colorFrame = colorFrame
        self.frameRate = frameRate
        self.userBits = userBits
        self.isValid = isValid
    }
}
