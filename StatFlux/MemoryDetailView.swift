import SwiftUI
import Darwin

struct MemoryDetailView: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let memory = statsStore.snapshot.memory {
                    overviewSection(memory)
                    breakdownSection(memory)
                    diagnosticsSection(memory)
                } else {
                    Text("Memory snapshot unavailable.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Memory Details")
    #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
    #endif
    }

    private func overviewSection(_ memory: MemoryStat) -> some View {
        GroupBox("Usage") {
            VStack(alignment: .leading, spacing: 12) {
                let totals = formattedTotals(memory)
                if let usageRatio = usageRatio(memory) {
                    ProgressView(value: usageRatio) {
                        Text("Used Memory")
                    } currentValueLabel: {
                        Text(Self.byteFormatter.string(fromByteCount: Int64(memory.usedBytes)))
                    }
                    .accessibilityValue(usageRatio, format: .percent)
                }

                Text("Total Physical Memory: \(totals.total)")
                    .font(.subheadline)
                Text("Available Memory: \(totals.free)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Sampled \(statsStore.snapshot.timestamp, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func breakdownSection(_ memory: MemoryStat) -> some View {
        GroupBox("Breakdown") {
            VStack(alignment: .leading, spacing: 8) {
                breakdownRow(title: "Wired", bytes: memory.wiredBytes)
                breakdownRow(title: "Compressed", bytes: memory.compressedBytes)
                if let active = statsStore.derivedMemoryDetail?.activeBytes {
                    breakdownRow(title: "Active", bytes: active)
                }
                if let inactive = statsStore.derivedMemoryDetail?.inactiveBytes {
                    breakdownRow(title: "Inactive", bytes: inactive)
                }
                if let free = statsStore.derivedMemoryDetail?.freeBytes {
                    breakdownRow(title: "Free", bytes: free)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diagnosticsSection(_ memory: MemoryStat) -> some View {
        GroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                if let pressure = statsStore.derivedMemoryDetail?.memoryPressureStatus {
                    detailRow(title: "Memory Pressure", value: pressure)
                }

                if let swap = statsStore.derivedMemoryDetail?.swapUsage {
                    detailRow(title: "Swap Used", value: Self.byteFormatter.string(fromByteCount: Int64(swap)))
                }

                if let footprint = statsStore.derivedMemoryDetail?.physicalFootprint {
                    detailRow(title: "App Footprint", value: Self.byteFormatter.string(fromByteCount: Int64(footprint)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func breakdownRow(title: String, bytes: UInt64) -> some View {
        let formatted = Self.byteFormatter.string(fromByteCount: Int64(bytes))
        return HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatted)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func formattedTotals(_ memory: MemoryStat) -> (total: String, free: String) {
        let totalString = Self.byteFormatter.string(fromByteCount: Int64(memory.totalBytes))
        let freeBytes = memory.totalBytes > memory.usedBytes ? memory.totalBytes - memory.usedBytes : 0
        let freeString = Self.byteFormatter.string(fromByteCount: Int64(freeBytes))
        return (total: totalString, free: freeString)
    }

    private func usageRatio(_ memory: MemoryStat) -> Double? {
        guard memory.totalBytes > 0 else { return nil }
        let ratio = Double(memory.usedBytes) / Double(memory.totalBytes)
        return max(0, min(1, ratio))
    }
}

private extension SystemStatsStore {
    var derivedMemoryDetail: DerivedMemoryDetail? {
        MemoryDiagnostics.fetch()
    }
}

private enum MemoryDiagnostics {
    static func fetch() -> DerivedMemoryDetail? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, pointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        var pressureLevel = Int32(0)
        var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("vm.memory_pressure", &pressureLevel, &pressureSize, nil, 0) != 0 {
            pressureLevel = -1
        }

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) != 0 {
            swapUsage.xsu_used = 0
        }

        var footprint: UInt64 = 0
        var footprintSize = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize_app", &footprint, &footprintSize, nil, 0) != 0 {
            footprint = 0
        }

        return DerivedMemoryDetail(
            activeBytes: UInt64(stats.active_count) * UInt64(vm_kernel_page_size),
            inactiveBytes: UInt64(stats.inactive_count) * UInt64(vm_kernel_page_size),
            freeBytes: UInt64(stats.free_count) * UInt64(vm_kernel_page_size),
            memoryPressureStatus: pressureDescription(pressureLevel),
            swapUsage: swapUsage.xsu_used,
            physicalFootprint: footprint
        )
    }

    private static func pressureDescription(_ level: Int32) -> String? {
        switch level {
        case 0: return "Normal"
        case 1: return "Warning"
        case 2: return "Critical"
        default: return nil
        }
    }
}

struct DerivedMemoryDetail {
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let freeBytes: UInt64
    let memoryPressureStatus: String?
    let swapUsage: UInt64?
    let physicalFootprint: UInt64?
}
