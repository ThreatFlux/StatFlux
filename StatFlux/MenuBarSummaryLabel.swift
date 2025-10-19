#if os(macOS)
import SwiftUI

struct MenuBarSummaryLabel: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(Color.accentColor)
            summaryContent
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var summaryContent: some View {
        HStack(spacing: 6) {
            cpuSummary
            separator
            labelSummary(prefix: "MEM", value: memoryPercent)
            separator
            labelSummary(prefix: "BAT", value: batteryPercent)
            separator
            labelSummary(prefix: "DISK", value: diskPercent)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
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

    private var cpuSummary: some View {
        (Text(Image(systemName: "gauge")) + Text(" \(cpuPercent)"))
            .monospacedDigit()
    }

    private func labelSummary(prefix: String, value: String) -> some View {
        Text("\(prefix) \(value)")
            .monospacedDigit()
    }

    private var separator: some View {
        Text("•")
            .foregroundStyle(.secondary)
    }
}
#endif
