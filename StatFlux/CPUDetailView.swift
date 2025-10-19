import SwiftUI

struct CPUDetailView: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let cpu = statsStore.snapshot.cpu {
                    overviewSection(cpu)
                    breakdownSection(cpu)
                    perCoreSection(cpu)
                    hardwareSection(cpu)
                } else {
                    Text("CPU information is not yet available.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("CPU Details")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func overviewSection(_ cpu: CPUStat) -> some View {
        GroupBox("Overview") {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: cpu.usage) {
                    Text("Overall Load")
                } currentValueLabel: {
                    Text(cpu.usage.formatted(.percent.precision(.fractionLength(0))))
                }

                if !cpu.loadAverages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Load Average")
                            .font(.subheadline.weight(.semibold))
                        Text(loadAverageString(cpu.loadAverages))
                            .font(.subheadline)
                    }
                }

                Text("Sampled \(statsStore.snapshot.timestamp, format: .relative(presentation: .numeric))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func breakdownSection(_ cpu: CPUStat) -> some View {
        GroupBox("Scheduler Breakdown") {
            VStack(alignment: .leading, spacing: 8) {
                if let breakdown = cpu.breakdown {
                    ForEach(breakdownItems(from: breakdown), id: \.label) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.label)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(item.value)
                                    .monospacedDigit()
                            }
                            ProgressView(value: item.percentage)
                        }
                    }
                } else {
                    Text("Breakdown data will appear shortly.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func perCoreSection(_ cpu: CPUStat) -> some View {
        GroupBox("Per-Core Activity") {
            VStack(alignment: .leading, spacing: 8) {
                if cpu.perCoreUsage.isEmpty {
                    Text("Per-core usage will appear after a few samples.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cpu.perCoreUsage) { core in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Core \(core.id + 1)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(core.usage.formatted(.percent.precision(.fractionLength(0))))
                                    .monospacedDigit()
                            }
                            ProgressView(value: core.usage)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hardwareSection(_ cpu: CPUStat) -> some View {
        GroupBox("Hardware") {
            VStack(alignment: .leading, spacing: 8) {
                if let brand = cpu.brand {
                    detailRow(title: "Processor", value: brand)
                }

                if let architecture = cpu.architecture {
                    detailRow(title: "Architecture", value: architecture.uppercased())
                }

                detailRow(title: "Logical Cores", value: "\(cpu.logicalCores)")

                if let physical = cpu.physicalCores {
                    detailRow(title: "Physical Cores", value: "\(physical)")
                }

                if let frequency = cpu.frequencyGHz {
                    detailRow(title: "Base Frequency", value: String(format: "%.2f GHz", frequency))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadAverageString(_ averages: [Double]) -> String {
        let formatted = averages.enumerated().map { index, value in
            let window: String
            switch index {
            case 0: window = "1m"
            case 1: window = "5m"
            case 2: window = "15m"
            default: window = "\(index + 1)m"
            }
            return "\(window): \(String(format: "%.2f", value))"
        }
        return formatted.joined(separator: " • ")
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func breakdownItems(from breakdown: CPUBreakdown) -> [(label: String, value: String, percentage: Double)] {
        [
            ("User", breakdown.user),
            ("System", breakdown.system),
            ("Nice", breakdown.nice),
            ("Idle", breakdown.idle)
        ]
            .filter { $0.1 > 0 }
            .map { (label, percentage) in
                (label, percentage.formatted(.percent.precision(.fractionLength(0))), percentage)
            }
    }
}
