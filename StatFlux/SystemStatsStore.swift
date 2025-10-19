import Combine
import Foundation
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
import IOKit.ps
import IOKit
import IOKit.graphics

@_silgen_name("IOPMCopyActivePMPreferences")
private func IOPMCopyActivePMPreferences() -> Unmanaged<CFDictionary>?
#endif
import Darwin

struct SystemStatsSnapshot {
    var cpu: CPUStat?
    var memory: MemoryStat?
    var battery: BatteryStat?
    var storage: StorageStat?
    var gpu: GPUStat?
    var batteryDetails: BatteryDetails?
    var timestamp: Date = Date()

    static let empty = SystemStatsSnapshot(cpu: nil, memory: nil, battery: nil, storage: nil, gpu: nil, batteryDetails: nil, timestamp: Date())
}

struct CPUCoreUsage: Identifiable {
    let id: Int
    let usage: Double
}

struct CPUBreakdown {
    let user: Double
    let system: Double
    let idle: Double
    let nice: Double
}

struct CPUStat {
    /// Overall CPU load in the range 0...1.
    let usage: Double
    /// Total logical/schedulable cores.
    let logicalCores: Int
    /// Physical core count when available.
    let physicalCores: Int?
    /// 1, 5, 15 minute load averages when available.
    let loadAverages: [Double]
    /// Per-core utilization values.
    let perCoreUsage: [CPUCoreUsage]
    /// CPU marketing/brand string.
    let brand: String?
    /// Reported clock speed in GHz.
    let frequencyGHz: Double?
    /// Machine architecture identifier.
    let architecture: String?
    /// Usage breakdown by scheduler state.
    let breakdown: CPUBreakdown?
}

struct MemoryStat {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
}

struct GPUStat {
    /// Overall GPU activity (0...1) when available.
    let deviceUtilization: Double?
    /// Renderer pipeline utilization (0...1) when available.
    let rendererUtilization: Double?
    /// Tiler pipeline utilization (0...1) when available.
    let tilerUtilization: Double?
    /// Total GPU-resident system memory currently in use.
    let inUseMemoryBytes: UInt64?
    /// GPU system memory attributed to drivers.
    let driverMemoryBytes: UInt64?
    /// Total GPU system memory allocation.
    let allocatedMemoryBytes: UInt64?
    /// Reported GPU core count when available.
    let coreCount: Int?
    /// Marketing / hardware model string when available.
    let model: String?
    /// Number of GPU clusters/GP blocks when available.
    let clusterCount: Int?
    /// Number of multi-GPU partitions when available.
    let multiGPUCount: Int?
    /// Active core counts per cluster when available.
    let coresPerCluster: [Int]?
    /// Reported architecture or variant identifier.
    let architecture: String?
    /// Current power state reported by IOPM.
    let powerState: Int?
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
    enum EnergyMode: Equatable {
        case lowPower
        case automatic
        case highPower
        case custom(String)

        var description: String {
            switch self {
            case .lowPower:
                return "Low Power"
            case .automatic:
                return "Automatic"
            case .highPower:
                return "High Power"
            case let .custom(label):
                return label
            }
        }
    }

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
    let energyMode: EnergyMode?
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
    private var previousCoreLoads: [Int: CPUCoreTicks] = [:]
    private var previousGPUDeviceUtilization: Double?
    private var previousGPURendererUtilization: Double?
    private var previousGPUTilerUtilization: Double?

    func collect() -> SystemStatsSnapshot {
        var snapshot = SystemStatsSnapshot.empty
        snapshot.cpu = fetchCPUUsage()
        snapshot.memory = fetchMemoryUsage()
        snapshot.gpu = fetchGPUUsage()
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

        if !hasPreviousCPULoad {
            _ = fetchPerCoreUsage(computeDifferences: false)
        }

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
        let logicalCores = max(1, Int(sysconf(Int32(_SC_NPROCESSORS_ONLN))))
        let physicalCores = sysctlInt("hw.physicalcpu")
        let brand = sysctlString("machdep.cpu.brand_string")
        let frequency = sysctlUInt64("hw.cpufrequency").map { Double($0) / 1_000_000_000 }
        let architecture = architectureIdentifier()

        let breakdown = CPUBreakdown(
            user: max(0, min(1, userDiff / totalTicks)),
            system: max(0, min(1, systemDiff / totalTicks)),
            idle: max(0, min(1, idleDiff / totalTicks)),
            nice: max(0, min(1, niceDiff / totalTicks))
        )

        let perCoreUsage = fetchPerCoreUsage(computeDifferences: true)

        return CPUStat(
            usage: usage,
            logicalCores: logicalCores,
            physicalCores: physicalCores,
            loadAverages: validAverages,
            perCoreUsage: perCoreUsage,
            brand: brand,
            frequencyGHz: frequency,
            architecture: architecture,
            breakdown: breakdown
        )
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

    private func fetchGPUUsage() -> GPUStat? {
#if os(macOS)
        guard let matching = IOServiceMatching("IOAccelerator") else {
            return nil
        }

        var iterator: io_iterator_t = 0
        let serviceResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard serviceResult == KERN_SUCCESS else {
            return nil
        }
        defer {
            IOObjectRelease(iterator)
        }

        var deviceUtilizations: [Double] = []
        var rendererUtilizations: [Double] = []
        var tilerUtilizations: [Double] = []
        var inUseMemory: UInt64 = 0
        var driverMemory: UInt64 = 0
        var allocatedMemory: UInt64 = 0
        var model: String?
        var coreCount: Int?
        var clusterCount: Int?
        var multiGPUCount: Int?
        var coresPerCluster: [Int]?
        var architecture: String?
        var powerState: Int?

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            if let performance = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                if let value = Self.percentageValue(performance["Device Utilization %"]) {
                    deviceUtilizations.append(value)
                }
                if let value = Self.percentageValue(performance["Renderer Utilization %"]) {
                    rendererUtilizations.append(value)
                }
                if let value = Self.percentageValue(performance["Tiler Utilization %"]) {
                    tilerUtilizations.append(value)
                }
                if let value = Self.byteValue(performance["In use system memory"]) {
                    inUseMemory = inUseMemory &+ value
                }
                if let value = Self.byteValue(performance["In use system memory (driver)"]) {
                    driverMemory = driverMemory &+ value
                }
                if let value = Self.byteValue(performance["Alloc system memory"]) {
                    allocatedMemory = allocatedMemory &+ value
                }
            }

            if model == nil,
               let rawModel = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                if let string = rawModel as? String {
                    model = string.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let data = rawModel as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    model = string.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if coreCount == nil,
               let rawCores = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                coreCount = rawCores.intValue
            }

            if (clusterCount == nil || coresPerCluster == nil || architecture == nil || multiGPUCount == nil),
               let configuration = IORegistryEntryCreateCFProperty(service, "GPUConfigurationVariable" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                if clusterCount == nil,
                   let clusters = configuration["num_gps"] as? NSNumber {
                    clusterCount = clusters.intValue
                }
                if multiGPUCount == nil,
                   let multi = configuration["num_mgpus"] as? NSNumber {
                    multiGPUCount = multi.intValue
                }
                if coresPerCluster == nil,
                   let masks = configuration["core_mask_list"] as? [Any] {
                    let counts = masks.compactMap { mask -> Int? in
                        if let number = mask as? NSNumber {
                            let raw = number.uint64Value
                            return Int(raw.nonzeroBitCount)
                        }
                        return nil
                    }
                    if !counts.isEmpty {
                        coresPerCluster = counts
                    }
                }
                if architecture == nil,
                   let variant = configuration["gpu_var"] as? String {
                    architecture = variant.nilIfEmpty
                }
            }

            if powerState == nil,
               let powerInfo = IORegistryEntryCreateCFProperty(service, "IOPowerManagement" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let current = powerInfo["CurrentPowerState"] as? NSNumber {
                powerState = current.intValue
            }

            service = IOIteratorNext(iterator)
        }

        let deviceAverage = Self.average(deviceUtilizations)
        let rendererAverage = Self.average(rendererUtilizations)
        let tilerAverage = Self.average(tilerUtilizations)

        let smoothedDevice = smoothed(current: deviceAverage, previous: &previousGPUDeviceUtilization)
        let smoothedRenderer = smoothed(current: rendererAverage, previous: &previousGPURendererUtilization)
        let smoothedTiler = smoothed(current: tilerAverage, previous: &previousGPUTilerUtilization)

        if deviceAverage == nil,
           rendererAverage == nil,
           tilerAverage == nil,
           inUseMemory == 0,
           driverMemory == 0,
           allocatedMemory == 0,
           model == nil,
           coreCount == nil {
            return nil
        }

        let resolvedInUse = inUseMemory > 0 ? inUseMemory : nil
        let resolvedDriver = driverMemory > 0 ? driverMemory : nil
        let resolvedAllocated = allocatedMemory > 0 ? allocatedMemory : nil

        return GPUStat(
            deviceUtilization: smoothedDevice ?? deviceAverage,
            rendererUtilization: smoothedRenderer ?? rendererAverage,
            tilerUtilization: smoothedTiler ?? tilerAverage,
            inUseMemoryBytes: resolvedInUse,
            driverMemoryBytes: resolvedDriver,
            allocatedMemoryBytes: resolvedAllocated,
            coreCount: coreCount,
            model: model?.nilIfEmpty,
            clusterCount: clusterCount,
            multiGPUCount: multiGPUCount,
            coresPerCluster: coresPerCluster,
            architecture: architecture,
            powerState: powerState
        )
#else
        return nil
#endif
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
        let powerSourceState = description[kIOPSPowerSourceStateKey as String] as? String
        let isExternalConnected = powerSourceState.map { $0 == kIOPSACPowerValue }
        let batteryHealth = description[kIOPSBatteryHealthKey as String] as? String
        let manufacturer = description["Manufacturer"] as? String
        let deviceName = description[kIOPSNameKey as String] as? String
        let serialNumber = description["SerialNumber"] as? String
        let firmwareVersion = description["FirmwareVersion"] as? String ?? description["Firmware Version"] as? String
        let lowPowerActive: Bool = {
            if let boolValue = description["LPM Active"] as? Bool {
                return boolValue
            }
            if let numberValue = description["LPM Active"] as? NSNumber {
                return numberValue.intValue > 0
            }
            return false
        }()
        let energyMode = determineEnergyMode(powerSourceState: powerSourceState, lowPowerActive: lowPowerActive)

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
           adapterWatts == nil,
           energyMode == nil {
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
            adapterWatts: adapterWatts,
            energyMode: energyMode
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
            adapterWatts: nil,
            energyMode: nil
        )
#else
        return nil
#endif
    }

#if os(macOS)
    private func determineEnergyMode(powerSourceState: String?, lowPowerActive: Bool) -> BatteryDetails.EnergyMode? {
        if let frameworkMode = activePowerModeFromPrivateFramework() {
            return frameworkMode
        }

        if lowPowerActive {
            return .lowPower
        }

        if #available(macOS 12.0, *) {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                return .lowPower
            }
        }

        guard let preferences = IOPMCopyActivePMPreferences()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let sourceKey: String
        if powerSourceState == kIOPSACPowerValue as String {
            sourceKey = "AC Power"
        } else if powerSourceState == kIOPSBatteryPowerValue as String {
            sourceKey = "Battery Power"
        } else {
            sourceKey = "AC Power"
        }

        guard let settings = preferences[sourceKey] as? [String: Any] else {
            return nil
        }

        if let explicit = (settings["EnergyMode"] as? NSString)?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            let lowercased = explicit.lowercased()
            if lowercased.contains("high") {
                return .highPower
            }
            if lowercased.contains("low") {
                return .lowPower
            }
            if lowercased.contains("auto") {
                return .automatic
            }
            return .custom(explicit)
        }

        let lowSettingValue = (settings["LowPowerMode"] as? NSNumber)?.intValue
        let highSettingValue = (settings["HighPowerMode"] as? NSNumber)?.intValue

        if let highSettingValue {
            if highSettingValue == 2 {
                return .automatic
            }
            if highSettingValue >= 1 {
                return .highPower
            }
        }

        if let lowSettingValue {
            switch lowSettingValue {
            case 1:
                return .lowPower
            case 2:
                return .automatic
            default:
                break
            }
        }

        if lowSettingValue != nil || highSettingValue != nil {
            return .automatic
        }

        return nil
    }

    private func activePowerModeFromPrivateFramework() -> BatteryDetails.EnergyMode? {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/LowPowerMode.framework") else {
            return nil
        }

        if !bundle.isLoaded {
            guard bundle.load() else {
                return nil
            }
        }

        guard bundle.isLoaded,
              let modesClass = NSClassFromString("_PMPowerModes") as? NSObject.Type else {
            return nil
        }

        let sharedSelector = NSSelectorFromString("sharedInstance")
        guard modesClass.responds(to: sharedSelector),
              let sharedUnmanaged = modesClass.perform(sharedSelector) else {
            return nil
        }

        let manager = sharedUnmanaged.takeUnretainedValue()
        let currentSelector = NSSelectorFromString("currentPowerMode")
        guard (manager as AnyObject).responds(to: currentSelector),
              let modeUnmanaged = (manager as AnyObject).perform(currentSelector) else {
            return nil
        }

        let rawObject = modeUnmanaged.takeUnretainedValue()
        let rawValue: Int
        if let number = rawObject as? NSNumber {
            rawValue = number.intValue
        } else if let valueObject = rawObject as? Int {
            rawValue = valueObject
        } else {
            return nil
        }

        switch rawValue {
        case 1:
            return .lowPower
        case 2:
            return .highPower
        case 0:
            fallthrough
        default:
            return .automatic
        }
    }
#endif

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

    private func fetchPerCoreUsage(computeDifferences: Bool) -> [CPUCoreUsage] {
        var processorInfo: processor_info_array_t?
        var processorMsgCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )

        guard result == KERN_SUCCESS, let infoPointer = processorInfo else {
            return []
        }

        defer {
            let size = vm_size_t(Int(processorMsgCount) * MemoryLayout<integer_t>.size)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: UnsafeMutableRawPointer(infoPointer)),
                size
            )
        }

        let cpuInfoData = infoPointer.withMemoryRebound(
            to: processor_cpu_load_info_data_t.self,
            capacity: Int(processorCount)
        ) {
            Array(UnsafeBufferPointer(start: $0, count: Int(processorCount)))
        }

        var newTicks: [Int: CPUCoreTicks] = [:]
        var usages: [CPUCoreUsage] = []

        for (index, info) in cpuInfoData.enumerated() {
            let ticks = CPUCoreTicks(
                user: info.cpu_ticks.0,
                system: info.cpu_ticks.1,
                idle: info.cpu_ticks.2,
                nice: info.cpu_ticks.3
            )

            if computeDifferences, let previous = previousCoreLoads[index] {
                let userDiff = Double(ticks.user) - Double(previous.user)
                let systemDiff = Double(ticks.system) - Double(previous.system)
                let idleDiff = Double(ticks.idle) - Double(previous.idle)
                let niceDiff = Double(ticks.nice) - Double(previous.nice)
                let total = userDiff + systemDiff + idleDiff + niceDiff

                if total > 0 {
                    let usage = max(0, min(1, (total - idleDiff) / total))
                    usages.append(CPUCoreUsage(id: index, usage: usage))
                }
            }

            newTicks[index] = ticks
        }

        previousCoreLoads = newTicks
        return usages.sorted { $0.id < $1.id }
    }

#if os(macOS)
    private static func percentageValue(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber else {
            return nil
        }
        let value = number.doubleValue / 100.0
        guard value.isFinite else {
            return nil
        }
        return max(0, min(value, 1))
    }

    private static func byteValue(_ raw: Any?) -> UInt64? {
        guard let number = raw as? NSNumber else {
            return nil
        }
        let value = number.doubleValue
        guard value.isFinite, value >= 0 else {
            return nil
        }
        return UInt64(value)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        let mean = total / Double(values.count)
        guard mean.isFinite else { return nil }
        return max(0, min(mean, 1))
    }
#endif

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        guard result == 0 else { return nil }
        return Int(value)
    }

    private func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        guard result == 0 else { return nil }
        return value
    }

    private func sysctlString(_ name: String) -> String? {
        var length: size_t = 0
        guard sysctlbyname(name, nil, &length, nil, 0) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard sysctlbyname(name, &buffer, &length, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private func architectureIdentifier() -> String? {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return nil }
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { accum, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            accum.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? nil : identifier
    }
}

private struct CPUCoreTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension SystemStatsCollector {
    func smoothed(current: Double?, previous: inout Double?) -> Double? {
        guard let current else {
            return previous
        }

        let clamped = max(0, min(current, 1))

        let smoothed: Double
        if let previousValue = previous {
            let damping = 0.65
            smoothed = previousValue * damping + clamped * (1 - damping)
        } else {
            smoothed = clamped
        }

        previous = smoothed
        return smoothed
    }
}
