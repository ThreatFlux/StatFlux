#if os(macOS)
import SwiftUI

struct MenuBarSummaryLabel: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    var body: some View {
        HStack(spacing: 6) {
            statSummary(icon: "gauge", value: percentString(statsStore.snapshot.cpu?.usage))
            separator
            statSummary(icon: "chart.line.uptrend.xyaxis", value: gpuPercent)
            separator
            statSummary(icon: "memorychip", value: memoryPercent)
            separator
            statSummary(icon: batteryIcon, value: batteryPercent)
            separator
            statSummary(icon: "externaldrive.fill", value: diskPercent)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .fixedSize()
    }

    private var memoryPercent: String {
        guard let memory = statsStore.snapshot.memory,
              memory.totalBytes > 0
        else { return "--" }
        let ratio = Double(memory.usedBytes) / Double(memory.totalBytes)
        return percentString(ratio)
    }

    private var gpuPercent: String {
        let utilization = statsStore.snapshot.gpu?.deviceUtilization
            ?? statsStore.snapshot.gpu?.rendererUtilization
            ?? statsStore.snapshot.gpu?.tilerUtilization
        return percentString(utilization)
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

    private var batteryIcon: String {
        guard let level = statsStore.snapshot.battery?.level else {
            return "bolt.slash"
        }

        switch level {
        case ..<0.25:
            return "battery.0"
        case ..<0.5:
            return "battery.25"
        case ..<0.75:
            return "battery.50"
        case ..<0.95:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private func statSummary(icon: String, value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .monospacedDigit()
        }
    }

    private var separator: some View {
        Text("•")
            .foregroundStyle(.secondary)
    }
}
#endif
