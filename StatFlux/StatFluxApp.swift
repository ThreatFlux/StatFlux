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
        MenuBarExtra {
            MenuBarDashboard()
                .environmentObject(statsStore)
        } label: {
            MenuBarSummaryLabel()
                .environmentObject(statsStore)
        }
        .menuBarExtraStyle(.menu)
#endif
    }
}
