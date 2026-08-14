import Foundation
import SwiftData

enum CaptureKind: String, CaseIterable, Identifiable {
    case voice
    case image
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: "Voice"
        case .image: "Image"
        case .text: "Text"
        }
    }

    var symbol: String {
        switch self {
        case .voice: "waveform"
        case .image: "photo"
        case .text: "doc.text"
        }
    }
}

@Model
final class CaptureItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var typeRaw: String
    var title: String
    var bodyText: String
    var tagsText: String
    var collectionName: String
    var assetFileName: String?
    var durationSeconds: Double
    var isProcessing: Bool
    var transcriptionNotice: String?
    /// Archived capture blocks stay stored locally but are hidden from the active timeline, library, Smart Sort, and Mac search.
    var isArchived: Bool = false
    /// A note or recording can belong to a screenshot captured in the same Quick Capture session.
    var parentCaptureID: UUID?

    init(
        kind: CaptureKind,
        title: String,
        bodyText: String = "",
        tags: [String] = [],
        collectionName: String = "Inbox",
        assetFileName: String? = nil,
        durationSeconds: Double = 0,
        isProcessing: Bool = false,
        transcriptionNotice: String? = nil,
        isArchived: Bool = false,
        parentCaptureID: UUID? = nil
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.typeRaw = kind.rawValue
        self.title = title
        self.bodyText = bodyText
        self.tagsText = tags.joined(separator: ", ")
        self.collectionName = collectionName
        self.assetFileName = assetFileName
        self.durationSeconds = durationSeconds
        self.isProcessing = isProcessing
        self.transcriptionNotice = transcriptionNotice
        self.isArchived = isArchived
        self.parentCaptureID = parentCaptureID
    }

    var kind: CaptureKind {
        CaptureKind(rawValue: typeRaw) ?? .text
    }

    var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var previewText: String {
        if isProcessing { return "Processing locally…" }
        if let transcriptionNotice, !transcriptionNotice.isEmpty { return transcriptionNotice }
        if bodyText.isEmpty { return "No extracted text" }
        return bodyText.replacingOccurrences(of: "\n", with: " ")
    }

    static func suggestedTitle(from text: String, fallback: String) -> String {
        let firstMeaningfulLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? ""

        let cleaned = firstMeaningfulLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback }
        return String(cleaned.prefix(72))
    }

    static func suggestedTags(from text: String) -> [String] {
        let lowercased = text.lowercased()
        var tags: [String] = []

        if lowercased.contains("€") || lowercased.contains("receipt") || lowercased.contains("total") {
            tags.append("receipt")
        }
        if lowercased.contains("http://") || lowercased.contains("https://") || lowercased.contains("www.") {
            tags.append("link")
        }
        if lowercased.contains("meeting") || lowercased.contains("agenda") {
            tags.append("meeting")
        }

        return tags
    }
}
