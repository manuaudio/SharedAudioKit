//
//  MIDIEndpointInfo.swift
//  CoreMIDIKit
//
//  MIDI endpoint discovery and identification.
//

import Foundation
import CoreMIDI

/// Information about a MIDI endpoint (source or destination).
public struct MIDIEndpointInfo: Identifiable, Sendable {
    public let endpoint: MIDIEndpointRef
    public let name: String
    public let uniqueID: Int32
    public var id: Int32 { uniqueID }

    public init(endpoint: MIDIEndpointRef, name: String, uniqueID: Int32) {
        self.endpoint = endpoint
        self.name = name
        self.uniqueID = uniqueID
    }
}

// MARK: - Endpoint Helpers

/// Get the display name of a MIDI endpoint.
public func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var name: Unmanaged<CFString>?
    var status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
    if status == noErr, let n = name {
        return n.takeRetainedValue() as String
    }
    status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
    if status == noErr, let n = name {
        return n.takeRetainedValue() as String
    }
    return "Unknown"
}

/// Get the unique ID of a MIDI endpoint.
public func endpointUniqueID(_ endpoint: MIDIEndpointRef) -> Int32 {
    var uid: Int32 = 0
    MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid)
    return uid
}

/// Enumerate all MIDI sources.
public func enumerateMIDISources() -> [MIDIEndpointInfo] {
    var result: [MIDIEndpointInfo] = []
    let count = MIDIGetNumberOfSources()
    for i in 0..<count {
        let ep = MIDIGetSource(i)
        result.append(MIDIEndpointInfo(
            endpoint: ep,
            name: endpointName(ep),
            uniqueID: endpointUniqueID(ep)
        ))
    }
    return result
}

/// Enumerate all MIDI destinations.
public func enumerateMIDIDestinations() -> [MIDIEndpointInfo] {
    var result: [MIDIEndpointInfo] = []
    let count = MIDIGetNumberOfDestinations()
    for i in 0..<count {
        let ep = MIDIGetDestination(i)
        result.append(MIDIEndpointInfo(
            endpoint: ep,
            name: endpointName(ep),
            uniqueID: endpointUniqueID(ep)
        ))
    }
    return result
}

/// Find a MIDI destination by unique ID.
public func findDestinationByUniqueID(_ uid: Int32) -> MIDIEndpointRef? {
    var obj: MIDIObjectRef = 0
    var objType: MIDIObjectType = .other
    let status = MIDIObjectFindByUniqueID(MIDIUniqueID(uid), &obj, &objType)
    if status == noErr && obj != 0 && objType == .destination {
        return obj
    }
    return nil
}

/// Find a MIDI source by unique ID.
public func findSourceByUniqueID(_ uid: Int32) -> MIDIEndpointRef? {
    var obj: MIDIObjectRef = 0
    var objType: MIDIObjectType = .other
    let status = MIDIObjectFindByUniqueID(MIDIUniqueID(uid), &obj, &objType)
    if status == noErr && obj != 0 && objType == .source {
        return obj
    }
    return nil
}
