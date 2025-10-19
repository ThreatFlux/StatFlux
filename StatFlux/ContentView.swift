import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var statsStore: SystemStatsStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    NavigationLink {
                        CPUDetailView()
                            .environmentObject(statsStore)
                    } label: {
                        StatCard(icon: "gauge", title: "CPU Load", display: SystemStatsFormatter.cpu(from: statsStore.snapshot))
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MemoryDetailView()
                            .environmentObject(statsStore)
                    } label: {
                        StatCard(icon: "square.stack.3d.up", title: "Memory", display: SystemStatsFormatter.memory(from: statsStore.snapshot))
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        BatteryDetailView()
                            .environmentObject(statsStore)
                    } label: {
                        StatCard(icon: "bolt.fill", title: "Battery", display: SystemStatsFormatter.battery(from: statsStore.snapshot))
                    }
                    .buttonStyle(.plain)
                    StatCard(icon: "externaldrive.fill", title: "Storage", display: SystemStatsFormatter.storage(from: statsStore.snapshot))
                }
                .padding(.vertical, 16)

                Text("Last updated \(statsStore.snapshot.timestamp, format: .relative(presentation: .named))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)

                Text("StatFlux continuously samples CPU, memory, battery, and storage to keep you informed.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding(.horizontal, 16)
            .navigationTitle("System Overview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        statsStore.refresh()
                    } label: {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                statsStore.refresh()
            }
        }
    }
}

private struct StatCard: View {
    let icon: String
    let title: String
    let display: StatDisplayValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.9))
                    )

                Spacer()
            }

            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(display.primary)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Text(display.secondary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}
