import Combine
import Foundation
import IOKit

struct ComputerFanTelemetry: Equatable {
    var fanRPM: Double?
    var averageCPUTemperature: Double?

    static let unavailable = ComputerFanTelemetry(fanRPM: nil, averageCPUTemperature: nil)

    var fanRPMText: String {
        guard let fanRPM else {
            return "-- RPM"
        }

        return "\(Int(fanRPM.rounded())) RPM"
    }

    var averageCPUTemperatureText: String {
        guard let averageCPUTemperature else {
            return "--°C"
        }

        return "\(Int(averageCPUTemperature.rounded()))°C"
    }

    var accessibilityText: String {
        "\(fanRPMText), average CPU \(averageCPUTemperatureText)"
    }
}

@MainActor
final class ComputerFanTelemetryMonitor: ObservableObject {
    @Published private(set) var telemetry = ComputerFanTelemetry.unavailable

    private var timerCancellable: AnyCancellable?

    init() {
        refresh()
        timerCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    private func refresh() {
        Task.detached(priority: .utility) {
            let telemetry = SMCHardwareReader.readTelemetry()
            await MainActor.run { [weak self] in
                self?.telemetry = telemetry
            }
        }
    }
}

private enum SMCHardwareReader {
    private static let kernelIndexSMC: UInt32 = 2
    private static let smcCommandReadBytes: UInt8 = 5
    private static let smcCommandReadKeyInfo: UInt8 = 9
    private static let success: UInt8 = 0

    static func readTelemetry() -> ComputerFanTelemetry {
        guard let connection = SMCConnection() else {
            return .unavailable
        }

        let fanRPM = readFanRPM(connection: connection)
        let averageCPUTemperature = readAverageCPUTemperature(connection: connection)
        return ComputerFanTelemetry(fanRPM: fanRPM, averageCPUTemperature: averageCPUTemperature)
    }

    private static func readFanRPM(connection: SMCConnection) -> Double? {
        let fanCount = readNumericValue(for: "FNum", connection: connection)
            .map { max(0, Int($0.rounded(.down))) } ?? 1
        let speeds = (0 ..< max(1, fanCount)).compactMap { index in
            readNumericValue(for: "F\(index)Ac", connection: connection)
        }

        guard !speeds.isEmpty else {
            return nil
        }

        return speeds.reduce(0, +) / Double(speeds.count)
    }

    private static func readAverageCPUTemperature(connection: SMCConnection) -> Double? {
        let cpuTemperatureKeys = [
            "Te05", "Te0S", "Te09", "Te0H",
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
            "TC0C", "TC0P", "TC0E", "TC0F", "TC0D", "TC0H",
            "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C", "TC8C",
        ]
        let temperatures = cpuTemperatureKeys.compactMap {
            readNumericValue(for: $0, connection: connection)
        }
        .filter { $0 > 0 && $0 < 130 }

        guard !temperatures.isEmpty else {
            return nil
        }

        return temperatures.reduce(0, +) / Double(temperatures.count)
    }

    private static func readNumericValue(for key: String, connection: SMCConnection) -> Double? {
        guard let value = connection.readKey(key), value.result == success else {
            return nil
        }

        return value.numericValue
    }

    private final class SMCConnection {
        private let connection: io_connect_t

        init?() {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            guard service != IO_OBJECT_NULL else {
                return nil
            }
            defer { IOObjectRelease(service) }

            var connection = io_connect_t()
            let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
            guard result == kIOReturnSuccess else {
                return nil
            }

            self.connection = connection
        }

        deinit {
            IOServiceClose(connection)
        }

        func readKey(_ key: String) -> SMCValue? {
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.key = key.smcKeyCode
            input.data8 = smcCommandReadKeyInfo

            guard call(input: &input, output: &output) == kIOReturnSuccess, output.result == success else {
                return nil
            }

            let keyInfo = output.keyInfo
            input.keyInfo = keyInfo
            input.data8 = smcCommandReadBytes

            guard call(input: &input, output: &output) == kIOReturnSuccess else {
                return nil
            }

            return SMCValue(keyInfo: keyInfo, result: output.result, bytes: output.byteArray(size: keyInfo.dataSize))
        }

        private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
            let inputSize = MemoryLayout<SMCKeyData>.stride
            var outputSize = MemoryLayout<SMCKeyData>.stride
            return IOConnectCallStructMethod(
                connection,
                kernelIndexSMC,
                &input,
                inputSize,
                &output,
                &outputSize
            )
        }
    }
}

private struct SMCValue {
    let keyInfo: SMCKeyInfoData
    let result: UInt8
    let bytes: [UInt8]

    var numericValue: Double? {
        switch keyInfo.dataType.stringValue {
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        default:
            return nil
        }
    }
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = SMCBytes()

    func byteArray(size: UInt32) -> [UInt8] {
        Array(bytes.array.prefix(Int(size)))
    }
}

private struct SMCBytes {
    var byte0: UInt8 = 0
    var byte1: UInt8 = 0
    var byte2: UInt8 = 0
    var byte3: UInt8 = 0
    var byte4: UInt8 = 0
    var byte5: UInt8 = 0
    var byte6: UInt8 = 0
    var byte7: UInt8 = 0
    var byte8: UInt8 = 0
    var byte9: UInt8 = 0
    var byte10: UInt8 = 0
    var byte11: UInt8 = 0
    var byte12: UInt8 = 0
    var byte13: UInt8 = 0
    var byte14: UInt8 = 0
    var byte15: UInt8 = 0
    var byte16: UInt8 = 0
    var byte17: UInt8 = 0
    var byte18: UInt8 = 0
    var byte19: UInt8 = 0
    var byte20: UInt8 = 0
    var byte21: UInt8 = 0
    var byte22: UInt8 = 0
    var byte23: UInt8 = 0
    var byte24: UInt8 = 0
    var byte25: UInt8 = 0
    var byte26: UInt8 = 0
    var byte27: UInt8 = 0
    var byte28: UInt8 = 0
    var byte29: UInt8 = 0
    var byte30: UInt8 = 0
    var byte31: UInt8 = 0

    var array: [UInt8] {
        [
            byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7,
            byte8, byte9, byte10, byte11, byte12, byte13, byte14, byte15,
            byte16, byte17, byte18, byte19, byte20, byte21, byte22, byte23,
            byte24, byte25, byte26, byte27, byte28, byte29, byte30, byte31,
        ]
    }
}

private extension String {
    var smcKeyCode: UInt32 {
        unicodeScalars.prefix(4).reduce(UInt32(0)) { result, scalar in
            (result << 8) + UInt32(scalar.value)
        }
    }
}

private extension UInt32 {
    var stringValue: String {
        let scalars = [
            UnicodeScalar((self >> 24) & 0xff),
            UnicodeScalar((self >> 16) & 0xff),
            UnicodeScalar((self >> 8) & 0xff),
            UnicodeScalar(self & 0xff),
        ]
        return String(String.UnicodeScalarView(scalars.compactMap { $0 }))
    }
}
