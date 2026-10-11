import SwiftUI

/// The iPhone app is a thin native shell: the whole interface is index.html in a web view,
/// and the native side adds what a web page can't do, which is reading HealthKit.
@main
struct BaselineApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var web = WebController()

    var body: some Scene {
        WindowGroup {
            WebView(controller: web)
                .ignoresSafeArea()
                .background(Color(red: 7 / 255, green: 8 / 255, blue: 11 / 255))
        }
        .onChange(of: scenePhase) { _, phase in
            // the page syncs itself on load; coming back to the foreground nudges it to sync again
            if phase == .active { web.foreground() }
        }
    }
}
