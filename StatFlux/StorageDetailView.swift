import SwiftUI
import Darwin

struct StorageDetailView: View {
    @EnvironmentObject private var statsStore: SystemStatsStore

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private let volumeInfo = VolumeInfo.fetch()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let storage = statsStore.snapshot.storage {
                    overviewSection(storage)
                    allocationsSection()
                    freeSpaceSection()
                    volumeSection()
                    capabilitySection()
                } else {
                    Text("Storage data unavailable.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Storage Details")
    #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
    #endif
    }

    private func overviewSection(_ storage: StorageStat) -> some View {
        GroupBox("Overview") {
            VStack(alignment: .leading, spacing: 12) {
                if let total = storage.totalBytes {
                    let used = total > storage.availableBytes ? total - storage.availableBytes : 0
                    let ratio = Double(used) / Double(total)
                    ProgressView(value: ratio) {
                        Text("Used Space")
                    } currentValueLabel: {
                        Text(Self.byteFormatter.string(fromByteCount: Int64(used)))
                    }

                    Text("Total Capacity: \(Self.byteFormatter.string(fromByteCount: Int64(total)))")
                        .font(.subheadline)
                    Text("Free Capacity: \(Self.byteFormatter.string(fromByteCount: Int64(storage.availableBytes)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Utilization: \(ratio.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Available free space: \(Self.byteFormatter.string(fromByteCount: Int64(storage.availableBytes)))")
                        .font(.subheadline)
                }

                Text("Sampled \(statsStore.snapshot.timestamp, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func allocationsSection() -> some View {
        GroupBox("Data Sets") {
            VStack(alignment: .leading, spacing: 8) {
                if let info = volumeInfo, let documents = info.documentDirectorySize {
                    detailRow(title: "Documents Folder", value: Self.byteFormatter.string(fromByteCount: Int64(documents)))
                } else {
                    Text("Detailed data usage unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func freeSpaceSection() -> some View {
        GroupBox("Free Space Options") {
            VStack(alignment: .leading, spacing: 8) {
                let items = freeSpaceItems()
                if items.isEmpty {
                    Text("Additional free-space metrics unavailable.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items, id: \.label) { entry in
                        detailRow(title: entry.label, value: Self.byteFormatter.string(fromByteCount: Int64(entry.value)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func volumeSection() -> some View {
        GroupBox("Volume") {
            VStack(alignment: .leading, spacing: 8) {
                if let info = volumeInfo {
                    if let name = info.name {
                        detailRow(title: "Name", value: name)
                    }

                    detailRow(title: "Mount Path", value: info.rootPath)

                    if let fsType = info.fileSystemType {
                        detailRow(title: "File System", value: fsType.uppercased())
                    }

                    if let uuid = info.uuidString {
                        detailRow(title: "Volume UUID", value: uuid)
                    }
                } else {
                    Text("Volume metadata unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func capabilitySection() -> some View {
        GroupBox("Capabilities") {
            VStack(alignment: .leading, spacing: 8) {
                if let info = volumeInfo {
                    capabilityRow(title: "Encrypted", value: info.isEncrypted)
                    capabilityRow(title: "Case Sensitive", value: info.isCaseSensitive)
                    capabilityRow(title: "Supports Compression", value: info.supportsCompression)
                    capabilityRow(title: "Supports File Cloning", value: info.supportsCloning)
                    capabilityRow(title: "Supports Sparse Files", value: info.supportsSparseFiles)
                } else {
                    Text("Capability information unavailable.")
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
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func capabilityRow(title: String, value: Bool?) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            if let value {
                Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(value ? .green : .red)
            } else {
                Text("Unknown")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private func freeSpaceItems() -> [(label: String, value: UInt64)] {
        guard let info = volumeInfo else { return [] }
        var items: [(label: String, value: UInt64)] = []
        if let important = info.importantAvailable {
            items.append(("Reserved (Important)", important))
        }
        if let opportunistic = info.opportunisticAvailable {
            items.append(("On-Demand (Opportunistic)", opportunistic))
        }
        return items
    }

    private struct VolumeInfo {
        let rootPath: String
        let name: String?
        let fileSystemType: String?
        let uuidString: String?
        let isEncrypted: Bool?
        let isCaseSensitive: Bool?
        let supportsCompression: Bool?
        let supportsCloning: Bool?
        let supportsSparseFiles: Bool?
        let importantAvailable: UInt64?
        let opportunisticAvailable: UInt64?
        let documentDirectorySize: UInt64?

        static func fetch() -> VolumeInfo? {
            let rootURL = URL(fileURLWithPath: NSHomeDirectory())
            do {
                let resourceValues = try rootURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeLocalizedNameKey,
                    .volumeUUIDStringKey,
                    .volumeIsEncryptedKey,
                    .volumeSupportsCompressionKey,
                    .volumeSupportsSparseFilesKey,
                    .volumeSupportsFileCloningKey,
                    .volumeSupportsCaseSensitiveNamesKey,
                    .volumeAvailableCapacityForImportantUsageKey,
                    .volumeAvailableCapacityForOpportunisticUsageKey
                ])

                let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                let documentsSize = docURL.flatMap { url in
                    try? directorySize(at: url)
                }

                let fsType = fileSystemType(for: rootURL.path)

                return VolumeInfo(
                    rootPath: rootURL.path,
                    name: resourceValues.volumeLocalizedName ?? resourceValues.volumeName,
                    fileSystemType: fsType,
                    uuidString: resourceValues.volumeUUIDString,
                    isEncrypted: resourceValues.volumeIsEncrypted,
                    isCaseSensitive: resourceValues.volumeSupportsCaseSensitiveNames,
                    supportsCompression: resourceValues.volumeSupportsCompression,
                    supportsCloning: resourceValues.volumeSupportsFileCloning,
                    supportsSparseFiles: resourceValues.volumeSupportsSparseFiles,
                    importantAvailable: resourceValues.volumeAvailableCapacityForImportantUsage.map { UInt64($0) },
                    opportunisticAvailable: resourceValues.volumeAvailableCapacityForOpportunisticUsage.map { UInt64($0) },
                    documentDirectorySize: documentsSize
                )
            } catch {
                return nil
            }
        }

        private static func directorySize(at url: URL) throws -> UInt64 {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            var total: UInt64 = 0
            while let fileURL = enumerator?.nextObject() as? URL {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += UInt64(size)
                }
            }
            return total
        }

        private static func fileSystemType(for path: String) -> String? {
            var stats = statfs()
            guard statfs(path, &stats) == 0 else { return nil }
            return withUnsafePointer(to: &stats.f_fstypename) { pointer -> String? in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                    String(validatingUTF8: $0)
                }
            }
        }
    }
}
