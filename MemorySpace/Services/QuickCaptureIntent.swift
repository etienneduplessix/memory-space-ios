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

struct SaveScreenshotToMemorySpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Screenshot to Memory Space"
    static var description = IntentDescription("Save a screenshot locally, extract its text, and open Quick Capture.")
    static var openAppWhenRun = true

    @Parameter(title: "Screenshot") var screenshot: IntentFile

    func perform() async throws -> some IntentResult {
        let fileName = try LocalFileStore.save(data: screenshot.data, fileExtension: "png")
        let item = CaptureItem(
            kind: .image,
            title: "Screenshot",
            assetFileName: fileName,
            isProcessing: true
        )

        let container = try MemorySpaceStore.makeContainer()
        let context = ModelContext(container)
        context.insert(item)
        try context.save()

        let extractedText = await TextExtractor.extractText(from: screenshot.data)
        item.bodyText = extractedText
        item.title = CaptureItem.suggestedTitle(from: extractedText, fallback: "Screenshot")
        item.tagsText = CaptureItem.suggestedTags(from: extractedText).joined(separator: ", ")
        item.isProcessing = false
        try context.save()

        UserDefaults.standard.set(true, forKey: "quickCaptureRequested")
        return .result()
    }
}
