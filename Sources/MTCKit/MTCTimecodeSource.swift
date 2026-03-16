//
//  MTCTimecodeSource.swift
//  MTCKit
//
//  Bridges MTCDecoder to the TimecodeSource protocol for use with TimecodeRouter.
//

import Foundation
import TimecodeKit

/// TimecodeSource wrapper for MTCDecoder.
///
/// Reads directly from the decoder's published properties — no manual update needed.
public final class MTCTimecodeSource: TimecodeSource {
    public let sourceID: String
    public var priority: Int
    private let decoder: MTCDecoder

    public init(decoder: MTCDecoder, sourceID: String = "mtc", priority: Int = 20) {
        self.decoder = decoder
        self.sourceID = sourceID
        self.priority = priority
    }

    public var currentTimecode: Timecode { decoder.timecode }
    public var currentRate: FrameRate { decoder.frameRate }
    public var isActive: Bool { decoder.isActive }
}
