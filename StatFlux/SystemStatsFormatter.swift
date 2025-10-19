import Foundation

struct StatDisplayValue {
    let primary: String
    let secondary: String
}

enum SystemStatsFormatter {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func cpu(from snapshot: SystemStatsSnapshot) -> StatDisplayValue {
        guard let cpu = snapshot.cpu else {
            return StatDisplayValue(primary: "--", secondary: "Collecting load data…")
        }

        let primary = "\(percentString(cpu.usage)) load"

        if cpu.loadAverages.isEmpty {
            return StatDisplayValue(primary: primary, secondary: coreSummary(cpu))
        }

        let peaks = cpu.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: " / ")
        var details = ["Load avg: \(peaks)"]
        let coreInfo = coreSummary(cpu)
        if !coreInfo.isEmpty {
            details.append(coreInfo)
        }
        return StatDisplayValue(primary: primary, secondary: details.joined(separator: " • "))
    }

    static func memory(from snapshot: SystemStatsSnapshot) -> StatDisplayValue {
        guard let memory = snapshot.memory else {
            return StatDisplayValue(primary: "--", secondary: "Calculating memory pressure…")
        }

        let usage = usagePercentString(used: memory.usedBytes, total: memory.totalBytes)
        let used = byteFormatter.string(fromByteCount: Int64(memory.usedBytes))
        let total = byteFormatter.string(fromByteCount: Int64(memory.totalBytes))
        let primary = usage.map { "\($0) used" } ?? "\(used) / \(total)"

        let wired = byteFormatter.string(fromByteCount: Int64(memory.wiredBytes))
        let compressed = byteFormatter.string(fromByteCount: Int64(memory.compressedBytes))
        let secondary = "\(used) of \(total) • Wired \(wired) • Compressed \(compressed)"
        return StatDisplayValue(primary: primary, secondary: secondary)
    }

    static func gpu(from snapshot: SystemStatsSnapshot) -> StatDisplayValue {
        guard let gpu = snapshot.gpu else {
            return StatDisplayValue(primary: "--", secondary: "Waiting for GPU metrics…")
        }

        let primary: String
        if let utilization = gpu.deviceUtilization {
            primary = "\(percentString(utilization)) active"
        } else if let renderer = gpu.rendererUtilization {
            primary = "\(percentString(renderer)) renderer"
        } else if let tiler = gpu.tilerUtilization {
            primary = "\(percentString(tiler)) tiler"
        } else {
            primary = "--"
        }

        var details: [String] = []

        if let renderer = gpu.rendererUtilization {
            details.append("Renderer \(percentString(renderer))")
        }
        if let tiler = gpu.tilerUtilization {
            details.append("Tiler \(percentString(tiler))")
        }
        if let memory = gpu.inUseMemoryBytes {
            let used = byteFormatter.string(fromByteCount: Int64(memory))
            if let total = gpu.allocatedMemoryBytes {
                let totalString = byteFormatter.string(fromByteCount: Int64(total))
                details.append("Memory \(used) / \(totalString)")
            } else {
                details.append("Memory \(used)")
            }
        } else if let driver = gpu.driverMemoryBytes {
            let driverString = byteFormatter.string(fromByteCount: Int64(driver))
            details.append("Driver Memory \(driverString)")
        }
        if let model = gpu.model {
            details.append(model)
        }
        if let cores = gpu.coreCount {
            details.append("\(cores) cores")
        }

        if details.isEmpty {
            details.append("Sampling GPU statistics…")
        }

        return StatDisplayValue(primary: primary, secondary: details.uniqued().joined(separator: " • "))
    }

    static func battery(from snapshot: SystemStatsSnapshot) -> StatDisplayValue {
        guard let battery = snapshot.battery else {
            return StatDisplayValue(primary: "--", secondary: "Battery data unavailable.")
        }

        let primary: String
        if let level = battery.level {
            primary = percentString(level)
        } else {
            primary = battery.statusDescription
        }

        var components: [String] = [battery.statusDescription]

        if let isCharging = battery.isCharging {
            components.append(isCharging ? "Charging" : "Discharging")
        }

        if let remaining = battery.timeRemaining,
           let formatted = timeFormatter.string(from: remaining) {
            components.append("~\(formatted) remaining")
        }

        let secondary = components.uniqued().joined(separator: " • ")
        return StatDisplayValue(primary: primary, secondary: secondary)
    }

    static func storage(from snapshot: SystemStatsSnapshot) -> StatDisplayValue {
        guard let storage = snapshot.storage else {
            return StatDisplayValue(primary: "--", secondary: "Storage data unavailable.")
        }

        let available = byteFormatter.string(fromByteCount: Int64(storage.availableBytes))
        if let total = storage.totalBytes, total > 0 {
            let totalFormatted = byteFormatter.string(fromByteCount: Int64(total))
            let used = total > storage.availableBytes ? total - storage.availableBytes : 0
            let usedFormatted = byteFormatter.string(fromByteCount: Int64(used))
            let usage = usagePercentString(used: used, total: total)
            let primary = usage.map { "\($0) used" } ?? "\(usedFormatted) used"
            return StatDisplayValue(primary: primary, secondary: "\(usedFormatted) of \(totalFormatted) used • \(available) free")
        } else {
            return StatDisplayValue(primary: "\(available) available", secondary: "Waiting for total capacity…")
        }
    }
}

private extension SystemStatsFormatter {
    static func percentString(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func usagePercentString(used: UInt64, total: UInt64) -> String? {
        guard total > 0 else { return nil }
        let ratio = Double(used) / Double(total)
        guard ratio.isFinite else { return nil }
        return percentString(max(0, min(ratio, 1)))
    }

    static func coreSummary(_ cpu: CPUStat) -> String {
        var parts: [String] = ["\(cpu.logicalCores) logical"]
        if let physical = cpu.physicalCores {
            parts.append("\(physical) physical")
        }
        return parts.joined(separator: " / ")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
