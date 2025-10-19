import SwiftUI

@main
struct StatFluxApp: App {
    @StateObject private var statsStore = SystemStatsStore()

    var body: some Scene {
        WindowGroup("StatFlux Dashboard", id: "mainDashboard") {
            ContentView()
                .environmentObject(statsStore)
        }
#if os(macOS)
        MenuBarExtra("StatFlux", systemImage: "chart.xyaxis.line") {
            MenuBarDashboard()
                .environmentObject(statsStore)
        }
        .menuBarExtraStyle(.window)
#endif
    }
}
