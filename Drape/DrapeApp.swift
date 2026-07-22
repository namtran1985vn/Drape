import SwiftUI
import UserNotifications

@main
struct DrapeApp: App {
    init() {
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    var body: some Scene {
        WindowGroup {
            ComposerView()
        }
    }
}
