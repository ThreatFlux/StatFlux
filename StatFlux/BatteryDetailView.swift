import SwiftUI

struct BatteryDetailView: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                diagnosticsSection
                capacitySection
                powerSection
                adapterSection
                metadataSection
            }
            .padding()
        }
        .navigationTitle("Battery Details")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
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

                    if let details = statsStore.snapshot.batteryDetails {
                        if let energyMode = details.energyMode {
                            detailRow(title: "Energy Mode", value: energyMode.description)
                        }
                        if let minutes = details.timeToEmptyMinutes, minutes > 0 {
                            detailRow(title: "Time to Empty", value: Self.timeFormatter.string(from: TimeInterval(minutes) * 60) ?? "--")
                        }
                        if let minutes = details.timeToFullMinutes, minutes > 0 {
                            detailRow(title: "Time to Full", value: Self.timeFormatter.string(from: TimeInterval(minutes) * 60) ?? "--")
                        }
                    } else if let remaining = battery.timeRemaining {
                        let formatted = Self.timeFormatter.string(from: remaining) ?? "--"
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
        GroupBox("Health") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = statsStore.snapshot.batteryDetails {
                    if let health = details.batteryHealth {
                        detailRow(title: "Battery Health", value: health)
                    }

                    if let temperature = details.temperatureCelsius {
                        let measurement = Measurement(value: temperature, unit: UnitTemperature.celsius)
                        detailRow(title: "Temperature", value: Self.temperatureFormatter.string(from: measurement))
                    }

                    if let cycleCount = details.cycleCount {
                        detailRow(title: "Cycle Count", value: "\(cycleCount)")
                    }
                } else {
                    Text("Diagnostics unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capacitySection: some View {
        GroupBox("Capacity") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = statsStore.snapshot.batteryDetails {
                    if let current = details.currentCapacitymAh {
                        detailRow(title: "Current Capacity", value: Self.capacityFormatter.string(from: current))
                    }

                    if let full = details.fullyChargedCapacitymAh {
                        detailRow(title: "Full Charge Capacity", value: Self.capacityFormatter.string(from: full))
                    }

                    if let design = details.designCapacitymAh {
                        detailRow(title: "Design Capacity", value: Self.capacityFormatter.string(from: design))
                        if let full = details.fullyChargedCapacitymAh, design > 0 {
                            let health = max(min(full / design, 1), 0)
                            detailRow(title: "Capacity Health", value: health.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                } else {
                    Text("No capacity data available.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var powerSection: some View {
        GroupBox("Power & Charging") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = statsStore.snapshot.batteryDetails {
                    if let voltage = details.voltage {
                        detailRow(title: "Battery Voltage", value: Self.voltageFormatter.string(from: voltage))
                    }

                    if let amperage = details.amperagemA {
                        detailRow(title: "Battery Current", value: Self.currentFormatter.string(from: amperage))
                    }

                    if let watts = details.wattage {
                        detailRow(title: "Battery Power", value: Self.wattFormatter.string(from: watts))
                    }
                } else {
                    Text("Power data unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var adapterSection: some View {
        GroupBox("Adapter") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = statsStore.snapshot.batteryDetails {
                    if let connected = details.isExternalConnected {
                        detailRow(title: "External Power", value: connected ? "Connected" : "Disconnected")
                    }

                    if let volts = details.adapterVoltage {
                        detailRow(title: "Adapter Voltage", value: Self.voltageFormatter.string(from: volts))
                    }

                    if let current = details.adapterAmperagemA {
                        detailRow(title: "Adapter Current", value: Self.currentFormatter.string(from: current))
                    }

                    if let watts = details.adapterWatts {
                        detailRow(title: "Adapter Power", value: Self.wattFormatter.string(from: watts))
                    }
                } else {
                    Text("Adapter information unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metadataSection: some View {
        GroupBox("Device") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = statsStore.snapshot.batteryDetails {
                    if let manufacturer = details.manufacturer {
                        detailRow(title: "Manufacturer", value: manufacturer)
                    }

                    if let deviceName = details.deviceName {
                        detailRow(title: "Battery Name", value: deviceName)
                    }

                    if let serial = details.serialNumber {
                        detailRow(title: "Serial Number", value: serial)
                    }

                    if let firmware = details.firmwareVersion {
                        detailRow(title: "Firmware Version", value: firmware)
                    }
                } else {
                    Text("No device metadata available.")
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

private extension BatteryDetailView {
    static let timeFormatter = DateComponentsFormatter.positional

    static let capacityFormatter: CapacityFormatter = CapacityFormatter()
    static let voltageFormatter: VoltageFormatter = VoltageFormatter()
    static let currentFormatter: CurrentFormatter = CurrentFormatter()
    static let wattFormatter: WattFormatter = WattFormatter()
    static let temperatureFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .medium
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()

    final class CapacityFormatter {
        private let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }()

        func string(from value: Double) -> String {
            let number = NSNumber(value: value)
            let formatted = formatter.string(from: number) ?? "\(Int(value))"
            return "\(formatted) mAh"
        }
    }

    final class VoltageFormatter {
        private let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        func string(from value: Double) -> String {
            let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
            return "\(formatted) V"
        }
    }

    final class CurrentFormatter {
        private let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }()

        func string(from value: Double) -> String {
            let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
            return "\(formatted) mA"
        }
    }

    final class WattFormatter {
        private let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }()

        func string(from value: Double) -> String {
            let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
            return "\(formatted) W"
        }
    }
}
