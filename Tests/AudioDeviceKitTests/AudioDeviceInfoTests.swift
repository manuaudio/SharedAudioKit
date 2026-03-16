#if os(macOS)
import Testing
@testable import AudioDeviceKit

@Suite("AudioDeviceInfo")
struct AudioDeviceInfoTests {

    @Test("AudioDeviceInfo has correct Identifiable conformance")
    func identifiable() {
        let info = AudioDeviceInfo(
            id: 42,
            uid: "test-uid",
            name: "Test Device",
            inputChannels: 8,
            outputChannels: 2
        )
        #expect(info.id == 42)
        #expect(info.uid == "test-uid")
        #expect(info.name == "Test Device")
        #expect(info.inputChannels == 8)
        #expect(info.outputChannels == 2)
    }

    @Test("Format sample rate display")
    func formatSampleRate() {
        #expect(AudioDeviceEnumerator.formatSampleRate(48000) == "48 kHz")
        #expect(AudioDeviceEnumerator.formatSampleRate(96000) == "96 kHz")
        #expect(AudioDeviceEnumerator.formatSampleRate(44100) == "44 kHz")
    }
}
#endif
