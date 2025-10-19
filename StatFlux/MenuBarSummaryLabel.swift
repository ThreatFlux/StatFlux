#if os(macOS)
import SwiftUI

struct MenuBarSummaryLabel: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(Color.accentColor)
            Text(summaryText)
                .monospacedDigit()
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }

    private var summaryText: String {
        [
            "CPU \(cpuPercent)",
            "MEM \(memoryPercent)",
            "BAT \(batteryPercent)",
            "DISK \(diskPercent)"
        ]
        .joined(separator: " • ")
    }

    private var cpuPercent: String {
        percentString(statsStore.snapshot.cpu?.usage)
    }

    private var memoryPercent: String {
        guard let memory = statsStore.snapshot.memory,
              memory.totalBytes > 0
        else { return "--" }
        let ratio = Double(memory.usedBytes) / Double(memory.totalBytes)
        return percentString(ratio)
    }

    private var batteryPercent: String {
        percentString(statsStore.snapshot.battery?.level)
    }

    private var diskPercent: String {
        guard let storage = statsStore.snapshot.storage,
              let total = storage.totalBytes,
              total > 0
        else { return "--" }
        let used = total > storage.availableBytes ? total - storage.availableBytes : 0
        let ratio = Double(used) / Double(total)
        return percentString(ratio)
    }

    private func percentString(_ value: Double?) -> String {
        guard let value else { return "--" }
        let clamped = max(0, min(value, 1))
        return clamped.formatted(.percent.precision(.fractionLength(0)))
    }
}
#endif
