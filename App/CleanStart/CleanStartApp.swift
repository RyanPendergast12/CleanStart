import SwiftUI

@main
struct CleanStartApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.dns)
                .environmentObject(model.network)
                .environmentObject(model.screenTime)
                .environmentObject(model.restrictions)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            // Automatic verification every time the app is opened.
            if phase == .active { Task { await model.refreshOnOpen() } }
        }
        .backgroundTask(.appRefresh(AppModel.backgroundTaskID)) {
            await AppModel.performBackgroundVerification()
        }
    }
}
