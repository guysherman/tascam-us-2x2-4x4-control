//
//  TascamUSB.swift
//  Native USB control layer for the TASCAM US-2x2 / US-4x4.
//
//  The protocol below was reconstructed from the original
//  "US-2x2_US-4x4_SettingsPanel" (TASCAM, 2016) application.
//
//  All requests are vendor requests on endpoint 0:
//
//    bmRequestType 0xC0 (IN) / 0x40 (OUT), recipient = device
//
//    bRequest  meaning                     wValue     wIndex          len
//    --------  --------------------------  ---------  --------------  ---
//    0x01      get firmware version        -          -               2
//    0x03      get auto power save         -          -               1
//    0x05      get audio input on/off      -          channel         1
//    0x07      get direct monitor mode     -          input pair      1
//    0x09      get line output routing     -          output pair     1
//    0x04      set auto power save         on/off     -               0
//    0x06      set audio input on/off      on/off     channel         0
//    0x08      set direct monitor mode     mode       input pair      0
//    0x0A      set line output routing     route      output pair     0
//
//  Direct monitor: 0 = mono, 1 = stereo.
//  Line output routing: 0 = Monitor Mix, 1 = Computer Out 1-2,
//                       2 = Computer Out 3-4.
//
//  The sample rate is read with a standard USB Audio Class 2 request:
//  GET_CUR on the SAMPLING_FREQUENCY_CONTROL of the clock source.
//

import Foundation
import IOKit
import IOUSBHost

// MARK: - Model information

enum TascamModel: UInt16, CaseIterable {
    case us2x2 = 0x8045
    case us4x4 = 0x804E

    var displayName: String {
        switch self {
        case .us2x2: return "US-2x2"
        case .us4x4: return "US-4x4"
        }
    }

    var inputChannels: Int {
        switch self {
        case .us2x2: return 2
        case .us4x4: return 4
        }
    }

    /// Number of stereo input/output pairs (also the number of device-side
    /// indices for the direct monitor and line output controls).
    var pairs: Int {
        switch self {
        case .us2x2: return 1
        case .us4x4: return 2
        }
    }

    var lineOutputOptions: [String] {
        switch self {
        case .us2x2:
            return ["Monitor Mix", "Computer Out 1-2"]
        case .us4x4:
            return ["Monitor Mix", "Computer Out 1-2", "Computer Out 3-4"]
        }
    }
}

// MARK: - Errors

enum TascamError: LocalizedError {
    case deviceNotFound
    case unsupportedModel
    case openFailed(String)
    case transferFailed(String)
    case shortResponse

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No TASCAM US-2x2 or US-4x4 was found."
        case .unsupportedModel:
            return "The connected device is not a supported TASCAM model."
        case .openFailed(let reason):
            return "The device could not be opened (\(reason))."
        case .transferFailed(let reason):
            return "USB request failed (\(reason))."
        case .shortResponse:
            return "The device returned a short response."
        }
    }
}

enum TascamDiscovery {
    case none
    /// A matching device was found but could not be opened.
    case unavailable(String)
    case found(TascamDevice)
}

// MARK: - Device

final class TascamDevice {
    static let vendorID: UInt16 = 0x0644

    let model: TascamModel
    let productName: String

    private let device: IOUSBHostDevice

    private init(device: IOUSBHostDevice, model: TascamModel, productName: String) {
        self.device = device
        self.model = model
        self.productName = productName
    }

    // MARK: Discovery

    /// Finds the first supported TASCAM interface.
    ///
    /// The audio interfaces are class-compliant, so macOS' audio driver owns
    /// them. IOUSBHostDevice opens the *device* side non-exclusively, which
    /// still allows vendor requests on endpoint 0 while audio is streaming.
    static func discover(queue: DispatchQueue) -> TascamDiscovery {
        guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else {
            return .none
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return .none }
        defer { IOObjectRelease(iterator) }

        var openError: String?

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            // Filter on vendor/product before opening anything. Matching on
            // CFNumber properties in the IOKit dictionary is unreliable
            // (numeric type must match exactly), so do it in code.
            guard let vendor = registryNumber(service, "idVendor"), vendor == vendorID,
                  let product = registryNumber(service, "idProduct"),
                  let model = TascamModel(rawValue: product) else {
                continue
            }

            do {
                let device = try IOUSBHostDevice(__ioService: service, options: [], queue: queue)
                let name = registryString(service, "USB Product Name") ?? model.displayName
                return .found(TascamDevice(device: device, model: model, productName: name))
            } catch {
                openError = error.localizedDescription
            }
        }

        if let openError {
            return .unavailable(openError)
        }
        return .none
    }

    private static func registryNumber(_ service: io_service_t, _ key: String) -> UInt16? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            return nil
        }
        return value.uint16Value
    }

    private static func registryString(_ service: io_service_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    // MARK: Low-level transfers

    @discardableResult
    private func requestIn(_ request: UInt8,
                           value: UInt16 = 0,
                           index: UInt16 = 0,
                           length: Int,
                           requestType: UInt8 = 0xC0) throws -> Data {
        var setup = IOUSBDeviceRequest()
        setup.bmRequestType = requestType
        setup.bRequest = request
        setup.wValue = value
        setup.wIndex = index
        setup.wLength = UInt16(length)

        let data = NSMutableData(length: length) ?? NSMutableData()
        var transferred = 0

        do {
            try device.__send(setup,
                              data: data,
                              bytesTransferred: &transferred,
                              completionTimeout: 1.0)
        } catch {
            throw TascamError.transferFailed(error.localizedDescription)
        }

        let count = transferred > 0 ? min(transferred, length) : length
        return Data((data as Data).prefix(count))
    }

    private func requestOut(_ request: UInt8,
                            value: UInt16 = 0,
                            index: UInt16 = 0) throws {
        var setup = IOUSBDeviceRequest()
        setup.bmRequestType = 0x40   // host-to-device, vendor, device
        setup.bRequest = request
        setup.wValue = value
        setup.wIndex = index
        setup.wLength = 0

        do {
            try device.__send(setup,
                              data: nil,
                              bytesTransferred: nil,
                              completionTimeout: 1.0)
        } catch {
            throw TascamError.transferFailed(error.localizedDescription)
        }
    }

    private func requestBool(_ request: UInt8, index: UInt16 = 0) throws -> Bool {
        let data = try requestIn(request, index: index, length: 1)
        guard let byte = data.first else { throw TascamError.shortResponse }
        return byte != 0
    }

    private func requestByte(_ request: UInt8, index: UInt16 = 0) throws -> UInt8 {
        let data = try requestIn(request, index: index, length: 1)
        guard let byte = data.first else { throw TascamError.shortResponse }
        return byte
    }

    // MARK: Reads

    /// Firmware version as a four-digit BCD value (e.g. 101 -> "1.01").
    func readFirmwareVersion() throws -> UInt16 {
        let data = try requestIn(0x01, length: 2)
        guard data.count >= 2 else { throw TascamError.shortResponse }
        let b0 = UInt16(data[data.startIndex])
        let b1 = UInt16(data[data.startIndex + 1])
        return (b0 >> 4) * 1000 + (b0 & 0x0F) * 100 + (b1 >> 4) * 10 + (b1 & 0x0F)
    }

    func readAutoPowerSave() throws -> Bool {
        try requestBool(0x03)
    }

    func readAudioInput(channel: Int) throws -> Bool {
        try requestBool(0x05, index: UInt16(channel))
    }

    func readDirectMonitor(pair: Int) throws -> Bool {
        try requestBool(0x07, index: UInt16(pair))
    }

    func readLineOutput(pair: Int) throws -> Int {
        Int(try requestByte(0x09, index: UInt16(pair)))
    }

    /// Reads the current sample rate (Hz) from the UAC2 clock source.
    func readSampleRate() -> UInt32? {
        guard let configuration = device.configurationDescriptor else {
            return nil
        }
        let totalLength = Int(configuration.pointee.wTotalLength)
        guard totalLength > 0 else { return nil }

        let bytes = UnsafeRawBufferPointer(start: configuration, count: totalLength)
        var offset = 0
        var interfaceNumber: UInt8 = 0
        var inUAC2AudioControl = false
        var clockID: UInt8?

        while offset + 2 <= totalLength {
            let length = Int(bytes[offset])
            if length == 0 { break }
            guard offset + length <= totalLength else { break }

            let type = bytes[offset + 1]
            if type == 0x04, length >= 9 {
                // Standard interface descriptor.
                interfaceNumber = bytes[offset + 2]
                let interfaceClass = bytes[offset + 5]
                let interfaceSubclass = bytes[offset + 6]
                let interfaceProtocol = bytes[offset + 7]
                inUAC2AudioControl = (interfaceClass == 1 &&
                                      interfaceSubclass == 1 &&
                                      interfaceProtocol == 0x20)
            } else if type == 0x24, length >= 4, inUAC2AudioControl {
                // Class-specific interface descriptor. Subtype 0x0A is a
                // clock source; bClockID follows the subtype.
                let subtype = bytes[offset + 2]
                if subtype == 0x0A {
                    clockID = bytes[offset + 3]
                    break
                }
            }

            offset += length
        }

        guard let clockID else { return nil }
        let index = (UInt16(clockID) << 8) | UInt16(interfaceNumber)

        // UAC2 GET_CUR, SAMPLING_FREQUENCY_CONTROL (0x0100), 32-bit little endian.
        guard let data = try? requestIn(0x01, value: 0x0100, index: index, length: 4,
                                        requestType: 0xA1),
              data.count >= 4 else {
            return nil
        }
        let b = [UInt8](data)
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }

    // MARK: Writes

    func setAutoPowerSave(_ enabled: Bool) throws {
        try requestOut(0x04, value: enabled ? 1 : 0)
    }

    func setAudioInput(channel: Int, enabled: Bool) throws {
        try requestOut(0x06, value: enabled ? 1 : 0, index: UInt16(channel))
    }

    func setDirectMonitor(pair: Int, stereo: Bool) throws {
        try requestOut(0x08, value: stereo ? 1 : 0, index: UInt16(pair))
    }

    func setLineOutput(pair: Int, route: Int) throws {
        guard route >= 0, route <= 2 else { return }
        try requestOut(0x0A, value: UInt16(route), index: UInt16(pair))
    }
}
