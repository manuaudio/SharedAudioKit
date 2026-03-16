//
//  AudioDeviceInfo.swift
//  AudioDeviceKit
//
//  CoreAudio device information.
//

import Foundation
import CoreAudio

/// Information about an audio device enumerated from CoreAudio HAL.
public struct AudioDeviceInfo: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let manufacturer: String

    public init(id: AudioDeviceID, uid: String, name: String,
                inputChannels: Int, outputChannels: Int, manufacturer: String = "") {
        self.id = id
        self.uid = uid
        self.name = name
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.manufacturer = manufacturer
    }

    public static func == (lhs: AudioDeviceInfo, rhs: AudioDeviceInfo) -> Bool {
        lhs.uid == rhs.uid
    }
}
