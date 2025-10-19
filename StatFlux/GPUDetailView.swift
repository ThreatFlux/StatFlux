import SwiftUI

struct GPUDetailView: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.isAdaptive = true
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let gpu = statsStore.snapshot.gpu {
                    overviewSection(gpu)
                    memorySection(gpu)
                    topologySection(gpu)
                    hardwareSection(gpu)
                } else {
                    Text("GPU metrics are not yet available. Sampling will begin shortly after launch.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("GPU Details")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func overviewSection(_ gpu: GPUStat) -> some View {
        GroupBox("Overview") {
            VStack(alignment: .leading, spacing: 12) {
                if let device = gpu.deviceUtilization {
                    ProgressView(value: device) {
                        Text("Overall Activity")
                    } currentValueLabel: {
                        Text(device.formatted(.percent.precision(.fractionLength(0))))
                    }
                } else {
                    Text("Overall GPU activity will appear shortly.")
                        .foregroundStyle(.secondary)
                }

                if let renderer = gpu.rendererUtilization {
                    utilizationRow(title: "Renderer", value: renderer)
                }

                if let tiler = gpu.tilerUtilization {
                    utilizationRow(title: "Tiler", value: tiler)
                }

                Text("Sampled \(statsStore.snapshot.timestamp, format: .relative(presentation: .numeric))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let state = gpu.powerState {
                    detailRow(title: "Power State", value: "\(state)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func memorySection(_ gpu: GPUStat) -> some View {
        GroupBox("Memory Usage") {
            VStack(alignment: .leading, spacing: 8) {
                if let inUse = gpu.inUseMemoryBytes {
                    let used = Self.byteFormatter.string(fromByteCount: Int64(inUse))
                    if let allocated = gpu.allocatedMemoryBytes {
                        let total = Self.byteFormatter.string(fromByteCount: Int64(allocated))
                        detailRow(title: "In Use", value: "\(used) of \(total)")
                    } else {
                        detailRow(title: "In Use", value: used)
                    }
                }

                if let driver = gpu.driverMemoryBytes {
                    let driverString = Self.byteFormatter.string(fromByteCount: Int64(driver))
                    detailRow(title: "Driver Memory", value: driverString)
                }

                if gpu.inUseMemoryBytes == nil,
                   gpu.driverMemoryBytes == nil,
                   gpu.allocatedMemoryBytes == nil {
                    Text("Memory statistics will appear once workloads engage the GPU.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func topologySection(_ gpu: GPUStat) -> some View {
        GroupBox("Topology") {
            VStack(alignment: .leading, spacing: 8) {
                if let clusters = gpu.clusterCount {
                    detailRow(title: "Clusters", value: "\(clusters)")
                }

                if let multi = gpu.multiGPUCount, multi > 1 {
                    detailRow(title: "Multi-GPU Units", value: "\(multi)")
                }

                if let clusterCores = gpu.coresPerCluster, !clusterCores.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cores per Cluster")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(clusterCores.enumerated()), id: \.offset) { index, count in
                            detailRow(title: "Cluster \(index + 1)", value: "\(count) cores active")
                        }
                    }
                }

                if gpu.clusterCount == nil,
                   gpu.coresPerCluster == nil,
                   gpu.multiGPUCount == nil {
                    Text("Topology data is not reported for this GPU.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hardwareSection(_ gpu: GPUStat) -> some View {
        GroupBox("Hardware") {
            VStack(alignment: .leading, spacing: 8) {
                if let model = gpu.model {
                    detailRow(title: "GPU", value: model)
                }

                if let cores = gpu.coreCount {
                    detailRow(title: "Core Count", value: "\(cores)")
                }

                if let architecture = gpu.architecture {
                    detailRow(title: "Variant", value: architecture.uppercased())
                }

                if gpu.model == nil, gpu.coreCount == nil {
                    Text("Hardware details unavailable for this device.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func utilizationRow(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
            }
            ProgressView(value: value)
        }
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
}
