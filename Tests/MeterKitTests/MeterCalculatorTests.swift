import Testing
@testable import MeterKit

@Suite("MeterCalculator")
struct MeterCalculatorTests {

    @Test("Silence returns -60 dB")
    func silenceFloor() {
        let silence = Array(repeating: Float(0.0), count: 512)
        let result = silence.withUnsafeBufferPointer { buf in
            MeterCalculator.calculateMeters(from: buf.baseAddress!, frameLength: 512)
        }
        #expect(result.rms == MeterCalculator.silenceDB)
        #expect(result.peak == MeterCalculator.silenceDB)
        #expect(result.clipped == false)
    }

    @Test("Full-scale sine clips")
    func fullScaleClips() {
        var buffer = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            buffer[i] = sin(Float(i) * 2.0 * .pi / 64.0)  // Full-scale sine
        }
        let result = buffer.withUnsafeBufferPointer { buf in
            MeterCalculator.calculateMeters(from: buf.baseAddress!, frameLength: 1024)
        }
        #expect(result.clipped == true)
        #expect(result.peak > -1.0)  // Should be near 0 dBFS
        #expect(result.rms > -10.0)  // RMS of sine is about -3 dBFS
    }

    @Test("K-System normalization range")
    func kSystemNormalize() {
        #expect(MeterCalculator.normalizeForKSystem(-60.0) == 0.0)
        #expect(MeterCalculator.normalizeForKSystem(0.0) == 1.0)
        #expect(MeterCalculator.normalizeForKSystem(-30.0) == 0.5)
        #expect(MeterCalculator.normalizeForKSystem(-70.0) == 0.0)  // Clamped
        #expect(MeterCalculator.normalizeForKSystem(10.0) == 1.0)   // Clamped
    }

    @Test("Color zones match K-System thresholds")
    func colorZones() {
        #expect(MeterCalculator.getColorZone(-30.0) == .green)
        #expect(MeterCalculator.getColorZone(-20.0) == .yellow)
        #expect(MeterCalculator.getColorZone(-15.0) == .orange)
        #expect(MeterCalculator.getColorZone(-5.0) == .red)
        #expect(MeterCalculator.getColorZone(0.0) == .red)
    }

    @Test("Empty buffer returns silence")
    func emptyBuffer() {
        let empty: [Float] = []
        let result = empty.withUnsafeBufferPointer { buf in
            MeterCalculator.calculateMeters(from: buf.baseAddress ?? UnsafePointer<Float>(bitPattern: 1)!, frameLength: 0)
        }
        #expect(result.rms == MeterCalculator.silenceDB)
        #expect(result.peak == MeterCalculator.silenceDB)
        #expect(result.clipped == false)
    }
}

@Suite("MeterStore")
struct MeterStoreTests {

    @Test("Reset meters restores silence")
    func resetMeters() {
        let store = MeterStore()
        store.writeMeters(rmsValues: [-10.0, -12.0], peakValues: [-5.0, -6.0])

        let (rms, peak) = store.getMeterData(channel: 0)
        #expect(rms == -10.0)
        #expect(peak == -5.0)

        store.resetMeters()

        let (rmsAfter, peakAfter) = store.getMeterData(channel: 0)
        #expect(rmsAfter == -60.0)
        #expect(peakAfter == -60.0)
    }

    @Test("Configurable refresh rate")
    func configurableRefreshRate() {
        let store = MeterStore()
        #expect(store.refreshRate == 30.0)

        // Setting refresh rate should not crash
        store.refreshRate = 60.0
        #expect(store.refreshRate == 60.0)

        store.refreshRate = 10.0
        #expect(store.refreshRate == 10.0)
    }

    @Test("Channel count reflects written data")
    func channelCount() {
        let store = MeterStore()
        #expect(store.channelCount == 0)

        store.writeMeters(rmsValues: [-20.0, -30.0], peakValues: [-10.0, -15.0])
        #expect(store.channelCount == 2)
    }
}
