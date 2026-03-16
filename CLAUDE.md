# CLAUDE.md — SharedAudioKit

SharedAudioKit is the shared audio infrastructure library for the Manu Audio ecosystem. It is a single Swift Package containing 8 library targets. Three macOS apps depend on it: RecSync, TC Trigger, and FXControl.

## Role

This is the heart of the ecosystem. Any audio infrastructure code that could be used by more than one app belongs here — not in the apps. When you add a playback engine to RecSync, TC Trigger gets sample playback for free. When FXControl's plugin host moves here, all apps can eventually insert FX.

## Package Structure

```
SharedAudioKit/
├── Package.swift              # Platforms: macOS 15+, iOS 17+, Swift 6.0+
├── Sources/
│   ├── TimecodeKit/           # Foundational — no dependencies on other modules
│   │   ├── Timecode.swift          # HH:MM:SS:FF struct, Codable, stored frameRate
│   │   ├── TimecodeComponents.swift # Rate-less HH:MM:SS:FF container
│   │   ├── FrameRate.swift         # 24/25/29.97df/30 fps, drop-frame math, Identifiable
│   │   ├── LockQuality.swift       # Signal quality for any sync source
│   │   ├── TimecodeRouter.swift    # Routes timecode from sources to consumers
│   │   └── TimecodeSource.swift    # Protocol for timecode providers
│   ├── RealTimeKit/           # Foundational — no dependencies on other modules
│   │   └── LockFreeRingBuffer.swift # SPSC ring buffer, atomic indices, 32768 frames
│   ├── CoreMIDIKit/           # Foundational — no dependencies on other modules
│   │   ├── MIDIManager.swift       # Single CoreMIDI client, input/output ports
│   │   ├── MIDIMessage.swift       # Parsed status/data1/data2/channel
│   │   ├── MIDIEndpointInfo.swift  # Source/destination metadata
│   │   ├── MIDISender.swift        # PC/CC/SysEx output with bank select
│   │   └── MTCGenerator.swift      # MTC quarter-frame output via MIDI
│   ├── AudioDeviceKit/        # Foundational — no dependencies on other modules
│   │   ├── AudioDeviceEnumerator.swift  # Lists input/output devices
│   │   └── AudioDeviceInfo.swift        # Device name, ID, channels, sample rate
│   ├── LTCKit/                # Depends on: TimecodeKit
│   │   ├── LTCDecoder.swift        # Real-time audio bit detector
│   │   ├── LTCEncoder.swift        # Generates LTC signal from timecode
│   │   ├── LTCFrame.swift          # Decoded frame with TC, sample position, rate
│   │   └── LTCTimecodeSource.swift # Conforms to TimecodeSource protocol
│   ├── MTCKit/                # Depends on: TimecodeKit
│   │   ├── MTCDecoder.swift        # Quarter-frame state machine, full-frame SysEx
│   │   └── MTCTimecodeSource.swift # Conforms to TimecodeSource protocol
│   ├── TriggerKit/            # Depends on: TimecodeKit
│   │   ├── CueTriggerEngine.swift       # Generic edge-triggered timecode cue engine
│   │   ├── TriggerCue.swift             # Protocol: triggerTC, enabled
│   │   ├── InternalClock.swift          # DispatchSourceTimer @ ~1/fps interval
│   │   └── InternalClockTimecodeSource.swift # Clock → timecode adapter
│   └── MeterKit/              # Depends on: RealTimeKit
│       ├── MeterCalculator.swift   # RMS + peak detection, real-time safe
│       ├── MeterStore.swift        # Lock-free meter value buffer
│       └── MetalMeterView.swift    # SwiftUI Metal view, 60 FPS GPU rendering
└── Tests/
    ├── TimecodeKitTests/
    ├── LTCKitTests/
    ├── MTCKitTests/
    ├── TriggerKitTests/
    ├── CoreMIDIKitTests/
    ├── AudioDeviceKitTests/
    ├── RealTimeKitTests/
    └── MeterKitTests/
```

## Dependency Graph

```
TimecodeKit ◄── LTCKit
             ◄── MTCKit
             ◄── TriggerKit

RealTimeKit ◄── MeterKit

CoreMIDIKit     (standalone)
AudioDeviceKit  (standalone)
```

## Platform Targets

- **macOS 15 Sequoia and above** — use latest Apple frameworks and APIs
- **iOS 17+** — for future TC Trigger iPad support
- **Swift 6** strict concurrency, swift-tools-version 6.0
- **Apple frameworks only** — no third-party dependencies

## Public API Surface

### TimecodeKit
- `Timecode` struct: `hours`, `minutes`, `seconds`, `frames`, `frameRate`. Codable, Equatable, Hashable.
  - Stored-rate API: `totalFrames`, `adding(frames:)`, `distance(to:)`, `components`
  - Rate-parameter API: `toFrames(rate:)`, `fromFrames(_:rate:)`, `adding(frames:rate:)`, `distance(to:rate:)`
  - Legacy API: `toFrames(fps:dropFrame:)`, `fromFrames(_:fps:dropFrame:)`
- `TimecodeComponents`: Rate-less `(h, m, s, f)` container with `toTimecode(frameRate:)` and `validated(for:)`.
- `FrameRate` enum: `.fps23976`, `.fps24`, `.fps25`, `.fps2997df`, `.fps30`. Identifiable, custom Codable.
  - `fromMtcRateBits(_:)`, `validatingFPS`, `framesPerSecond` alias, `fps2997Drop` alias
- `LockQuality`: Signal quality enum (`.good`, `.weak`, `.unstable`) for any sync source.
- `TimecodeSource` protocol: Any timecode provider conforms to this.
- `TimecodeRouter`: Routes from one or more TimecodeSource to consumers.

### CoreMIDIKit
- `MIDIManager`: `createInputPort(name:callback:)`, `createOutputPort(name:)`, `send(_:to:)`, `connectAllSources()`, `refreshEndpoints()`
- `MIDIMessage`: Parsed message with `status`, `data1`, `data2`, `channel`.
- `MIDIEndpointInfo`: `name`, `uniqueID`, `endpoint`. Equatable, Identifiable.
- `MIDISender`: MIDI output with `sendProgramChange`, `sendControlChange`, `sendSysEx` (bank select support).
- `MTCGenerator`: MTC quarter-frame output. `updateTimecode`, `updateDestination`, `start`/`stop`.

### AudioDeviceKit
- `AudioDeviceEnumerator`: `getAllDevices()`, `getInputDevices()`, `getOutputDevices()`
- `AudioDeviceInfo`: `name`, `deviceID`, `inputChannelCount`, `outputChannelCount`, `sampleRate`

### LTCKit
- `LTCDecoder`: Feed audio samples, get `LTCFrame` callbacks.
- `LTCEncoder`: Generate LTC audio signal from `Timecode`.
- `LTCFrame`: `timecode`, `samplePosition`, `frameRate`, `flags`.

### MTCKit
- `MTCDecoder`: Process MIDI bytes, get assembled timecode. Handles quarter-frame and full-frame SysEx.

### TriggerKit
- `CueTriggerEngine<T: TriggerCue>`: Generic engine fires when timecode crosses cue boundaries.
- `TriggerCue` protocol: `triggerTC: Timecode`, `enabled: Bool`.
- `InternalClock`: Frame-accurate timer for free-running mode.

### RealTimeKit
- `LockFreeRingBuffer`: `write(_:frameCount:)`, `read(_:frameCount:)`, `availableRead()`, `availableWrite()`. SPSC, atomic, allocation-free.

### MeterKit
- `MeterCalculator`: Feed audio samples, get RMS/peak values. Real-time safe.
- `MeterStore`: Lock-free shared meter state between audio and UI threads.
- `MetalMeterView`: Drop-in SwiftUI view for GPU-rendered meters.

## Communication Patterns

- **Delegates/protocols** for one-to-one callbacks (TimecodeSource, TriggerCue)
- **Combine publishers** where appropriate for UI-bound state
- **async/await** for non-real-time operations
- **Atomic/lock-free** for audio-thread communication (RealTimeKit, MeterKit)

## Code Rules

- Swift 6 strict concurrency. Public types: Sendable. Shared state: actor.
- Audio-thread code: no locks, no allocation, no ObjC messaging, no print().
- Apple frameworks only. No third-party dependencies.
- Semantic version tags. `swift test` must pass before tagging.
- Every public type and function needs documentation comments.

## How to Add a New Module

1. Create `Sources/NewModuleKit/` with Swift files.
2. Add a new library target in Package.swift.
3. Add dependency relationships if it uses other modules.
4. Create `Tests/NewModuleKitTests/` with unit tests.
5. Run `swift test` to verify everything builds.
6. Tag a new version.
7. Update each app's Package.swift resolved dependency.

## Current Status

All 8 modules are implemented and in use. The next phase involves extracting more duplicate code from the apps (MIDI engine patterns, OSC infrastructure, audio file I/O) into new or existing modules based on the cross-project audit.

## Locked Decisions

- **Single monorepo.** All 8 modules in one Package.swift. Not separate packages.
- **No CoreMIDI in MTCKit.** MTCKit only does byte-level decode. MTC output (MTCGenerator) lives in CoreMIDIKit.
- **No UI in non-MeterKit modules.** Only MeterKit has SwiftUI views. Everything else is headless.
- **LTC code lives here.** Never write LTC decode/encode inside an app.
