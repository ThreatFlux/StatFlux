#if os(macOS)
import SwiftUI

struct MenuBarSummaryLabel: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    var body: some View {
        summaryText
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
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

    private var summaryText: Text {
        statText(icon: "gauge", value: percentString(statsStore.snapshot.cpu?.usage))
        + separatorText
        + statText(icon: "memorychip", value: memoryPercent)
        + separatorText
        + statText(icon: batteryIcon, value: batteryPercent)
        + separatorText
        + statText(icon: "externaldrive.fill", value: diskPercent)
    }

    private func statText(icon: String, value: String) -> Text {
        Text(Image(systemName: icon)) + Text(" \(value)")
    }

    private var separatorText: Text {
        Text(" • ")
    }
}
#endif
