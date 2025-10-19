import Combine
import Foundation
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
import IOKit.ps
#endif
import Darwin

struct SystemStatsSnapshot {
    var cpu: CPUStat?
    var memory: MemoryStat?
    var battery: BatteryStat?
    var storage: StorageStat?
    var batteryDetails: BatteryDetails?
    var timestamp: Date = Date()

    static let empty = SystemStatsSnapshot(cpu: nil, memory: nil, battery: nil, storage: nil, batteryDetails: nil, timestamp: Date())
}

struct CPUStat {
    /// Overall CPU load in the range 0...1.
    let usage: Double
    /// Total logical cores available.
    let cores: Int
    /// 1, 5, 15 minute load averages when available.
    let loadAverages: [Double]
}

struct MemoryStat {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
}

struct BatteryStat {
    enum PowerSource {
        case ac
        case battery
        case unknown
    }

    /// Battery level in the range 0...1 when available.
    let level: Double?
    let isCharging: Bool?
    let statusDescription: String
    let timeRemaining: TimeInterval?
    let powerSource: PowerSource
}

struct BatteryDetails {
    let designCapacitymAh: Double?
    let fullyChargedCapacitymAh: Double?
    let currentCapacitymAh: Double?
    let cycleCount: Int?
    let temperatureCelsius: Double?
    let voltage: Double?
    let amperagemA: Double?
    let wattage: Double?
    let timeToEmptyMinutes: Int?
    let timeToFullMinutes: Int?
    let isExternalConnected: Bool?
    let batteryHealth: String?
    let manufacturer: String?
    let deviceName: String?
    let serialNumber: String?
    let firmwareVersion: String?
    let adapterAmperagemA: Double?
    let adapterVoltage: Double?
    let adapterWatts: Double?
}

struct StorageStat {
    let totalBytes: UInt64?
    let availableBytes: UInt64
}

final class SystemStatsStore: ObservableObject {
    @Published private(set) var snapshot: SystemStatsSnapshot = .empty

    private let collector = SystemStatsCollector()
    private var timerCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init(updateInterval: TimeInterval = 2) {
#if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
#endif

        refresh()

        timerCancellable = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    deinit {
        timerCancellable?.cancel()
#if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = false
#endif
    }

    func refresh() {
        snapshot = collector.collect()
    }
}

private final class SystemStatsCollector {
    private var previousCPULoad: host_cpu_load_info = host_cpu_load_info()
    private var hasPreviousCPULoad = false

    func collect() -> SystemStatsSnapshot {
        var snapshot = SystemStatsSnapshot.empty
        snapshot.cpu = fetchCPUUsage()
        snapshot.memory = fetchMemoryUsage()
        snapshot.battery = fetchBatteryStatus()
        snapshot.batteryDetails = fetchBatteryDetails()
        snapshot.storage = fetchStorageUsage()
        snapshot.timestamp = Date()
        return snapshot
    }

    private func fetchCPUUsage() -> CPUStat? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var load = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, pointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        defer {
            previousCPULoad = load
            hasPreviousCPULoad = true
        }

        guard hasPreviousCPULoad else {
            return nil
        }

        let userDiff = Double(load.cpu_ticks.0 - previousCPULoad.cpu_ticks.0)
        let systemDiff = Double(load.cpu_ticks.1 - previousCPULoad.cpu_ticks.1)
        let idleDiff = Double(load.cpu_ticks.2 - previousCPULoad.cpu_ticks.2)
        let niceDiff = Double(load.cpu_ticks.3 - previousCPULoad.cpu_ticks.3)

        let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
        guard totalTicks > 0 else {
            return nil
        }

        let busyTicks = totalTicks - idleDiff
        let usage = max(0, min(1, busyTicks / totalTicks))

        var averages = [Double](repeating: 0, count: 3)
        let loadCount = averages.withUnsafeMutableBufferPointer { buffer -> Int32 in
            getloadavg(buffer.baseAddress, 3)
        }

        let validAverages = loadCount > 0 ? Array(averages.prefix(Int(loadCount))) : []
        let coreCount = max(1, Int(sysconf(Int32(_SC_NPROCESSORS_ONLN))))

        return CPUStat(usage: usage, cores: coreCount, loadAverages: validAverages)
    }

    private func fetchMemoryUsage() -> MemoryStat? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, pointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize

        let used = active + inactive + wired + compressed + speculative
        let total = used + free

        return MemoryStat(usedBytes: used, totalBytes: total, wiredBytes: wired, compressedBytes: compressed)
    }

    private func fetchBatteryStatus() -> BatteryStat? {
#if os(iOS)
        let device = UIDevice.current
        let rawLevel = device.batteryLevel
        let level = rawLevel >= 0 ? Double(rawLevel) : nil

        let stateDescription: String
        let isCharging: Bool
        switch device.batteryState {
        case .charging:
            stateDescription = "Charging"
            isCharging = true
        case .full:
            stateDescription = "Full"
            isCharging = false
        case .unplugged:
            stateDescription = "On Battery"
            isCharging = false
        default:
            stateDescription = "Unknown"
            isCharging = false
        }

        let powerSource: BatteryStat.PowerSource = isCharging ? .ac : .battery
        return BatteryStat(level: level, isCharging: isCharging, statusDescription: stateDescription, timeRemaining: nil, powerSource: powerSource)
#elseif os(macOS)
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return BatteryStat(level: nil, isCharging: nil, statusDescription: "No Battery Data", timeRemaining: nil, powerSource: .unknown)
        }

        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef], let source = sources.first else {
            return BatteryStat(level: nil, isCharging: nil, statusDescription: "No Battery", timeRemaining: nil, powerSource: .unknown)
        }

        guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return BatteryStat(level: nil, isCharging: nil, statusDescription: "No Battery Data", timeRemaining: nil, powerSource: .unknown)
        }

        let isPresent = (description[kIOPSIsPresentKey] as? Bool) ?? false
        guard isPresent else {
            return BatteryStat(level: nil, isCharging: nil, statusDescription: "No Battery", timeRemaining: nil, powerSource: .unknown)
        }

        let currentCapacity = (description[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let maxCapacity = max((description[kIOPSMaxCapacityKey] as? Int) ?? 0, 1)
        let level = Double(currentCapacity) / Double(maxCapacity)

        let powerSourceValue = description[kIOPSPowerSourceStateKey] as? String
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let timeToEmpty = (description[kIOPSTimeToEmptyKey] as? Int) ?? -1
        let timeToFull = (description[kIOPSTimeToFullChargeKey] as? Int) ?? -1

        let timeRemainingMinutes: Int
        if timeToFull > 0 && isCharging {
            timeRemainingMinutes = timeToFull
        } else if timeToEmpty > 0 && !isCharging {
            timeRemainingMinutes = timeToEmpty
        } else {
            timeRemainingMinutes = -1
        }

        let powerSource: BatteryStat.PowerSource
        if powerSourceValue == kIOPSACPowerValue {
            powerSource = .ac
        } else if powerSourceValue == kIOPSBatteryPowerValue {
            powerSource = .battery
        } else {
            powerSource = .unknown
        }

        let status: String
        if isCharging {
            status = "Charging"
        } else if powerSource == .ac {
            status = "On AC Power"
        } else {
            status = "On Battery"
        }

        let timeInterval = timeRemainingMinutes > 0 ? TimeInterval(timeRemainingMinutes * 60) : nil

        return BatteryStat(level: level, isCharging: isCharging, statusDescription: status, timeRemaining: timeInterval, powerSource: powerSource)
#else
        return nil
#endif
    }

    private func fetchBatteryDetails() -> BatteryDetails? {
#if os(macOS)
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        func doubleValue(for key: String) -> Double? {
            if let value = description[key] as? Double {
                return value
            }
            if let value = description[key] as? Int {
                return Double(value)
            }
            return nil
        }

        let designCapacity = doubleValue(for: "DesignCapacity")
        let fullChargeCapacity = doubleValue(for: kIOPSMaxCapacityKey as String)
        let currentCapacity = doubleValue(for: kIOPSCurrentCapacityKey as String)
        let cycleCount = description["Cycle Count"] as? Int ?? description["CycleCount"] as? Int
        let temperature = doubleValue(for: "Temperature")
        let rawVoltage = doubleValue(for: "Voltage") ?? doubleValue(for: kIOPSVoltageKey as String)
        let rawAmperage = doubleValue(for: "Amperage")
        let rawWattage = doubleValue(for: "Watts")
        let timeToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int
        let timeToFull = description[kIOPSTimeToFullChargeKey as String] as? Int
        let isExternalConnected = description[kIOPSIsExternalPowerConnectedKey as String] as? Bool
        let batteryHealth = description[kIOPSBatteryHealthKey as String] as? String
        let manufacturer = description["Manufacturer"] as? String
        let deviceName = description[kIOPSNameKey as String] as? String
        let serialNumber = description["SerialNumber"] as? String
        let firmwareVersion = description["FirmwareVersion"] as? String ?? description["Firmware Version"] as? String

        var adapterVoltage: Double?
        var adapterAmperage: Double?
        var adapterWatts: Double?
        if let adapter = description["AdapterDetails"] as? [String: Any] {
            if let value = adapter["Voltage"] as? Double {
                adapterVoltage = value / 1000.0
            } else if let value = adapter["Voltage"] as? Int {
                adapterVoltage = Double(value) / 1000.0
            }
            if let value = adapter["Amperage"] as? Double {
                adapterAmperage = value
            } else if let value = adapter["Amperage"] as? Int {
                adapterAmperage = Double(value)
            }
            if let value = adapter["Watts"] as? Double {
                adapterWatts = value
            } else if let value = adapter["Watts"] as? Int {
                adapterWatts = Double(value)
            }
        }

        if designCapacity == nil,
           fullChargeCapacity == nil,
           currentCapacity == nil,
           cycleCount == nil,
           temperature == nil,
           rawVoltage == nil,
           rawAmperage == nil,
           rawWattage == nil,
           timeToEmpty == nil,
           timeToFull == nil,
           isExternalConnected == nil,
           batteryHealth == nil,
           manufacturer == nil,
           deviceName == nil,
           serialNumber == nil,
           firmwareVersion == nil,
           adapterVoltage == nil,
           adapterAmperage == nil,
           adapterWatts == nil {
            return nil
        }

        return BatteryDetails(
            designCapacitymAh: designCapacity,
            fullyChargedCapacitymAh: fullChargeCapacity,
            currentCapacitymAh: currentCapacity,
            cycleCount: cycleCount,
            temperatureCelsius: temperature.map { $0 / 100.0 },
            voltage: rawVoltage.map { $0 / 1000.0 },
            amperagemA: rawAmperage,
            wattage: rawWattage,
            timeToEmptyMinutes: timeToEmpty,
            timeToFullMinutes: timeToFull,
            isExternalConnected: isExternalConnected,
            batteryHealth: batteryHealth,
            manufacturer: manufacturer,
            deviceName: deviceName,
            serialNumber: serialNumber,
            firmwareVersion: firmwareVersion,
            adapterAmperagemA: adapterAmperage,
            adapterVoltage: adapterVoltage,
            adapterWatts: adapterWatts
        )
#elseif os(iOS)
        let device = UIDevice.current
        if device.batteryState == .unknown {
            return nil
        }
        return BatteryDetails(
            designCapacitymAh: nil,
            fullyChargedCapacitymAh: nil,
            currentCapacitymAh: nil,
            cycleCount: nil,
            temperatureCelsius: nil,
            voltage: nil,
            amperagemA: nil,
            wattage: nil,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil,
            isExternalConnected: nil,
            batteryHealth: nil,
            manufacturer: nil,
            deviceName: nil,
            serialNumber: nil,
            firmwareVersion: nil,
            adapterAmperagemA: nil,
            adapterVoltage: nil,
            adapterWatts: nil
        )
#else
        return nil
#endif
    }

    private func fetchStorageUsage() -> StorageStat? {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let resourceValues = try homeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey
            ])

            let availableImportant = resourceValues.volumeAvailableCapacityForImportantUsage.map { UInt64($0) }
            let availableFallback = resourceValues.volumeAvailableCapacity.map { UInt64($0) }
            guard let available = availableImportant ?? availableFallback else {
                return nil
            }
            let total = resourceValues.volumeTotalCapacity.map { UInt64($0) }
            return StorageStat(totalBytes: total, availableBytes: available)
        } catch {
            return nil
        }
    }
}
