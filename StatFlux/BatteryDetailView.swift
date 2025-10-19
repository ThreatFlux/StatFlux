import SwiftUI

struct BatteryDetailView: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                diagnosticsSection
                lifecycleSection
            }
            .padding()
        }
        .navigationTitle("Battery Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summarySection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                if let level = statsStore.snapshot.battery?.level {
                    ProgressView(value: level) {
                        Text("Charge Level")
                    } currentValueLabel: {
                        Text(level.formatted(.percent.precision(.fractionLength(0))))
                    }
                }

                if let battery = statsStore.snapshot.battery {
                    detailRow(title: "Power Source", value: powerSourceDescription(battery.powerSource))
                    detailRow(title: "State", value: battery.statusDescription)

                    if let remaining = battery.timeRemaining {
                        let formatted = DateComponentsFormatter.positional.string(from: remaining) ?? "--"
                        detailRow(title: "Estimated Time", value: formatted)
                    }
                } else {
                    Text("Battery information unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnosticsSection: some View {
        GroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = statsStore.snapshot.batteryDetails {
                    if let voltage = details.voltage {
                        detailRow(title: "Voltage", value: "\(voltage, specifier: "%.2f") V")
                    }

                    if let temperature = details.temperatureCelsius {
                        detailRow(title: "Temperature", value: "\(temperature, specifier: "%.1f") °C")
                    }
                } else {
                    Text("Diagnostics unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lifecycleSection: some View {
        GroupBox("Lifecycle") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = statsStore.snapshot.batteryDetails {
                    if let fullCapacity = details.fullyChargedCapacitymAh {
                        detailRow(title: "Full Charge Capacity", value: "\(Int(fullCapacity)) mAh")
                    }

                    if let designCapacity = details.designCapacitymAh {
                        detailRow(title: "Design Capacity", value: "\(Int(designCapacity)) mAh")
                    }

                    if let cycleCount = details.cycleCount {
                        detailRow(title: "Cycle Count", value: "\(cycleCount)")
                    }
                } else {
                    Text("No lifecycle data available.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    private func powerSourceDescription(_ source: BatteryStat.PowerSource) -> String {
        switch source {
        case .ac:
            return "AC Power"
        case .battery:
            return "Battery"
        case .unknown:
            return "Unknown"
        }
    }
}

private extension DateComponentsFormatter {
    static var positional: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }
}
