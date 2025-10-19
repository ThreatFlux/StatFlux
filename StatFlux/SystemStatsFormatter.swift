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

        let primary = cpu.usage.formatted(.percent.precision(.fractionLength(0...1)))

        if cpu.loadAverages.isEmpty {
            return StatDisplayValue(primary: primary, secondary: "\(cpu.cores) cores active")
        }

        let peaks = cpu.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: " / ")
        return StatDisplayValue(primary: primary, secondary: "Load avg: \(peaks)")
    }

    static func memory(from snapshot: SystemStatsSnapshot) -> StatDisplayValue {
        guard let memory = snapshot.memory else {
            return StatDisplayValue(primary: "--", secondary: "Calculating memory pressure…")
        }

        let used = byteFormatter.string(fromByteCount: Int64(memory.usedBytes))
        let total = byteFormatter.string(fromByteCount: Int64(memory.totalBytes))
        let primary = "\(used) / \(total)"

        let wired = byteFormatter.string(fromByteCount: Int64(memory.wiredBytes))
        let compressed = byteFormatter.string(fromByteCount: Int64(memory.compressedBytes))
        let secondary = "Wired \(wired) • Compressed \(compressed)"
        return StatDisplayValue(primary: primary, secondary: secondary)
    }

    static func battery(from snapshot: SystemStatsSnapshot) -> StatDisplayValue {
        guard let battery = snapshot.battery else {
            return StatDisplayValue(primary: "--", secondary: "Battery data unavailable.")
        }

        let primary: String
        if let level = battery.level {
            primary = level.formatted(.percent.precision(.fractionLength(0)))
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
        if let total = storage.totalBytes {
            let totalFormatted = byteFormatter.string(fromByteCount: Int64(total))
            let used = total > storage.availableBytes ? total - storage.availableBytes : 0
            let usedFormatted = byteFormatter.string(fromByteCount: Int64(used))
            return StatDisplayValue(primary: "\(available) free of \(totalFormatted)", secondary: "Used \(usedFormatted)")
        } else {
            return StatDisplayValue(primary: "\(available) available", secondary: "Waiting for total capacity…")
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
