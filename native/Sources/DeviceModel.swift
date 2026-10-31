//
//  DeviceModel.swift
//  Observable state for the settings panel.
//

import Foundation
import Combine

final class DeviceModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var connected = false
    @Published private(set) var modelName = "No Device"
    @Published private(set) var firmwareVersion = "—"
    @Published private(set) var sampleRate = "—"
    @Published private(set) var inputEnabled: [Bool] = [false, false, false, false]
    @Published private(set) var directMonitorStereo: [Bool] = [false, false]
    @Published private(set) var lineOutput: [Int] = [0, 0]
    @Published private(set) var autoPowerSave = false
    @Published private(set) var inputChannels = 2
    @Published private(set) var pairs = 1
    @Published private(set) var lineOutputOptions = TascamModel.us2x2.lineOutputOptions
    @Published private(set) var errorMessage: String?

    // MARK: Private state

    private let queue = DispatchQueue(label: "com.tascamuscontrol.usb", qos: .userInitiated)
    private var device: TascamDevice?
    private var timer: Timer?
    private var refreshing = false

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Polling

    func refresh() {
        queue.async { [weak self] in
            guard let self, !self.refreshing else { return }
            self.refreshing = true
            defer { self.refreshing = false }
            self.refreshLocked()
        }
    }

    private func refreshLocked() {
        #if DEBUG
        if let demo = ProcessInfo.processInfo.environment["TASCAM_DEMO"] {
            publish(Self.demoSnapshot(model: demo == "us2x2" ? .us2x2 : .us4x4))
            return
        }
        #endif

        if let device {
            do {
                let snapshot = try makeSnapshot(from: device)
                publish(snapshot)
            } catch {
                // The device was unplugged or stopped responding.
                self.device = nil
                publish(Snapshot.disconnected)
            }
            return
        }

        switch TascamDevice.discover(queue: queue) {
        case .found(let device):
            self.device = device
            do {
                publish(try makeSnapshot(from: device))
            } catch {
                self.device = nil
                publish(Snapshot.disconnected)
            }

        case .unavailable(let reason):
            var snapshot = Snapshot.disconnected
            snapshot.error = "Device found but could not be opened. \(reason)"
            publish(snapshot)

        case .none:
            publish(Snapshot.disconnected)
        }
    }

    private func makeSnapshot(from device: TascamDevice) throws -> Snapshot {
        // This first request doubles as a liveness check.
        let firmwareRaw = try device.readFirmwareVersion()

        var snapshot = Snapshot()
        snapshot.connected = true
        snapshot.modelName = device.model.displayName
        snapshot.inputChannels = device.model.inputChannels
        snapshot.pairs = device.model.pairs
        snapshot.lineOutputOptions = device.model.lineOutputOptions
        snapshot.firmwareVersion = Self.formatFirmware(firmwareRaw)
        snapshot.sampleRate = device.readSampleRate().map(Self.formatSampleRate) ?? "—"

        snapshot.autoPowerSave = (try? device.readAutoPowerSave()) ?? false

        for channel in 0..<snapshot.inputChannels {
            snapshot.inputEnabled[channel] = (try? device.readAudioInput(channel: channel)) ?? false
        }

        for pair in 0..<snapshot.pairs {
            snapshot.directMonitorStereo[pair] = (try? device.readDirectMonitor(pair: pair)) ?? false
            let route = (try? device.readLineOutput(pair: pair)) ?? 0
            snapshot.lineOutput[pair] = min(max(route, 0), snapshot.lineOutputOptions.count - 1)
        }

        return snapshot
    }

    private func publish(_ snapshot: Snapshot) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connected = snapshot.connected
            self.modelName = snapshot.modelName
            self.firmwareVersion = snapshot.firmwareVersion
            self.sampleRate = snapshot.sampleRate
            self.inputEnabled = snapshot.inputEnabled
            self.directMonitorStereo = snapshot.directMonitorStereo
            self.lineOutput = snapshot.lineOutput
            self.autoPowerSave = snapshot.autoPowerSave
            self.inputChannels = snapshot.inputChannels
            self.pairs = snapshot.pairs
            self.lineOutputOptions = snapshot.lineOutputOptions
            self.errorMessage = snapshot.error
        }
    }

    // MARK: User actions

    func setAudioInput(channel: Int, enabled: Bool) {
        guard connected, channel >= 0, channel < inputChannels else { return }
        inputEnabled[channel] = enabled

        queue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.setAudioInput(channel: channel, enabled: enabled)
            } catch {
                self.handleWriteFailure()
            }
        }
    }

    func setDirectMonitor(pair: Int, stereo: Bool) {
        guard connected, pair >= 0, pair < pairs else { return }
        directMonitorStereo[pair] = stereo

        queue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.setDirectMonitor(pair: pair, stereo: stereo)
            } catch {
                self.handleWriteFailure()
            }
        }
    }

    func setLineOutput(pair: Int, route: Int) {
        guard connected, pair >= 0, pair < pairs else { return }
        let clamped = min(max(route, 0), lineOutputOptions.count - 1)
        lineOutput[pair] = clamped

        queue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.setLineOutput(pair: pair, route: clamped)
            } catch {
                self.handleWriteFailure()
            }
        }
    }

    func setAutoPowerSave(_ enabled: Bool) {
        guard connected else { return }
        autoPowerSave = enabled

        queue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.setAutoPowerSave(enabled)
            } catch {
                self.handleWriteFailure()
            }
        }
    }

    private func handleWriteFailure() {
        device = nil
        publish(Snapshot.disconnected)
    }

    // MARK: Formatting

    private static func formatFirmware(_ raw: UInt16) -> String {
        String(format: "%d.%02d", raw / 100, raw % 100)
    }

    private static func formatSampleRate(_ hz: UInt32) -> String {
        let khz = Double(hz) / 1000.0
        if khz.rounded() == khz {
            return String(format: "%.0f kHz", khz)
        }
        return String(format: "%.1f kHz", khz)
    }

    #if DEBUG
    private static func demoSnapshot(model: TascamModel) -> Snapshot {
        var snapshot = Snapshot()
        snapshot.connected = true
        snapshot.modelName = model.displayName
        snapshot.firmwareVersion = "1.01"
        snapshot.sampleRate = "48 kHz"
        snapshot.inputChannels = model.inputChannels
        snapshot.pairs = model.pairs
        snapshot.lineOutputOptions = model.lineOutputOptions
        snapshot.autoPowerSave = true
        for channel in 0..<snapshot.inputChannels {
            snapshot.inputEnabled[channel] = true
        }
        for pair in 0..<snapshot.pairs {
            snapshot.directMonitorStereo[pair] = true
            snapshot.lineOutput[pair] = min(pair + 1, snapshot.lineOutputOptions.count - 1)
        }
        return snapshot
    }
    #endif
}

// MARK: - Snapshot

private struct Snapshot {
    var connected = false
    var modelName = "No Device"
    var firmwareVersion = "—"
    var sampleRate = "—"
    var inputEnabled: [Bool] = [false, false, false, false]
    var directMonitorStereo: [Bool] = [false, false]
    var lineOutput: [Int] = [0, 0]
    var autoPowerSave = false
    var inputChannels = 2
    var pairs = 1
    var lineOutputOptions = TascamModel.us2x2.lineOutputOptions
    var error: String?

    static let disconnected = Snapshot()
}
