import AppIntents
import Foundation

struct StartQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Capture"
    static var description = IntentDescription("Open Memory Space ready to record a thought or capture an image.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "quickCaptureRequested")
        return .result()
    }
}

struct MemorySpaceShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartQuickCaptureIntent(),
            phrases: [
                "Quick capture in \(.applicationName)",
                "Record a thought in \(.applicationName)"
            ],
            shortTitle: "Quick Capture",
            systemImageName: "mic.circle.fill"
        )
    }
}
