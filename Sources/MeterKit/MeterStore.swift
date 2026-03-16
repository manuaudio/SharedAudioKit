//
//  MeterStore.swift
//  MeterKit
//
//  Single source of truth for meter data.
//  Audio engine writes levels; Metal views read them.
//

import Foundation
import Observation

/// Thread-safe meter data store for cross-thread metering.
@Observable
public final class MeterStore {

    /// Interleaved: [ch0_rms, ch0_peak, ch1_rms, ch1_peak, ...]
    @ObservationIgnored private var meterData: [Float] = []
    @ObservationIgnored private let queue = DispatchQueue(label: "com.manuaudio.meters", qos: .userInteractive)

    /// Lightweight trigger for SwiftUI Metal view refresh (30Hz).
    public private(set) var refreshTrigger: Int = 0
    private var refreshTimer: DispatchSourceTimer?

    public init() {
        startRefreshTimer()
    }

    // MARK: - Write (from audio thread)

    public func writeMeters(rmsValues: [Float], peakValues: [Float]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let count = min(rmsValues.count, peakValues.count)
            if self.meterData.count != count * 2 {
                self.meterData = Array(repeating: -60.0, count: count * 2)
            }
            for i in 0..<count {
                self.meterData[i * 2] = rmsValues[i]
                self.meterData[i * 2 + 1] = peakValues[i]
            }
        }
    }

    // MARK: - Read (from Metal views)

    public func getMeterData(channel: Int) -> (rms: Float, peak: Float) {
        queue.sync {
            guard channel * 2 + 1 < meterData.count else {
                return (-60.0, -60.0)
            }
            return (meterData[channel * 2], meterData[channel * 2 + 1])
        }
    }

    public func getAllMeterData() -> [Float] {
        queue.sync { meterData }
    }

    public var channelCount: Int {
        queue.sync { meterData.count / 2 }
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in
            self?.refreshTrigger &+= 1
        }
        timer.resume()
        refreshTimer = timer
    }
}
