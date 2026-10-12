import SwiftUI

/// The iPhone app is a thin native shell: the whole interface is index.html in a web view,
/// and the native side adds what a web page can't do: HealthKit, widgets and the Live Activity, the coach's key.
@main
struct BaselineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

/// Health can launch the app in the background when new data arrives (sleep, workouts, HRV, water); the observers that
/// receive it have to be registered at launch, before any web page exists.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthReader.shared.startObserving()
        return true
    }
}
