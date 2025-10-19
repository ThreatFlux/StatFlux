#if os(macOS)
import AppKit
import SwiftUI

struct MenuBarDashboard: View {
    @EnvironmentObject private var statsStore: SystemStatsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatRow(label: "CPU", display: SystemStatsFormatter.cpu(from: statsStore.snapshot), icon: "gauge")
            StatRow(label: "GPU", display: SystemStatsFormatter.gpu(from: statsStore.snapshot), icon: "chart.line.uptrend.xyaxis")

            StatRow(label: "Memory", display: SystemStatsFormatter.memory(from: statsStore.snapshot), icon: "square.stack.3d.up")
            StatRow(label: "Battery", display: SystemStatsFormatter.battery(from: statsStore.snapshot), icon: "bolt.fill")
            StatRow(label: "Storage", display: SystemStatsFormatter.storage(from: statsStore.snapshot), icon: "externaldrive.fill")

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    openWindow(id: "mainDashboard")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Dashboard", systemImage: "rectangle.grid.2x2")
                }
                .buttonStyle(.plain)

                Button {
                    statsStore.refresh()
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit StatFlux", systemImage: "power")
                }
                .buttonStyle(.plain)
            }

            Text("Updated \(statsStore.snapshot.timestamp, format: .relative(presentation: .named))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 280)
    }
}

private struct StatRow: View {
    let label: String
    let display: StatDisplayValue
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(display.primary)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()

                Text(display.secondary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
