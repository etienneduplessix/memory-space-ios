import AppIntents
import Foundation
import SwiftData

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

struct FinishScreenshotCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Finish Screenshot Capture"
    static var description = IntentDescription("Import the screenshot that was just saved to Photos, then open Memory Space for a note or voice recording.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "importLatestScreenshotRequested")
        UserDefaults.standard.set(true, forKey: "quickCaptureRequested")
        return .result()
    }
}
