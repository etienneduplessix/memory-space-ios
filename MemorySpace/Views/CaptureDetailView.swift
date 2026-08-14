import SwiftData
import SwiftUI
import UIKit

struct CaptureDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var allItems: [CaptureItem]
    @Bindable var item: CaptureItem
    @State private var showsDeleteConfirmation = false

    private let collectionOptions = ["Inbox", "Ideas", "Work", "Personal", "Receipts", "Travel"]

    var body: some View {
        Form {
            if item.kind == .image, let image = localImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Details") {
                TextField("Title", text: $item.title, axis: .vertical)
                Picker("Collection", selection: $item.collectionName) {
                    ForEach(collectionOptions, id: \.self) { collection in
                        Text(collection).tag(collection)
                    }
                }
                LabeledContent("Captured") {
                    Text(item.createdAt, format: .dateTime.day().month().year().hour().minute())
                }
                if item.kind == .voice {
                    LabeledContent("Recording") {
                        Text(durationString(item.durationSeconds))
                    }
                }
            }

            Section("Extracted text") {
                if item.isProcessing {
                    HStack {
                        ProgressView()
                        Text("Processing locally…")
                    }
                }
                if let transcriptionNotice = item.transcriptionNotice, !transcriptionNotice.isEmpty {
                    Label(transcriptionNotice, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    TextEditor(text: $item.bodyText)
                        .frame(minHeight: 180)
                }
            }

            Section("Tags") {
                TextField("receipt, idea, meeting", text: $item.tagsText)
                    .textInputAutocapitalization(.never)
            }

            if let parentItem {
                Section("Attached to") {
                    NavigationLink {
                        CaptureDetailView(item: parentItem)
                    } label: {
                        Label(parentItem.title, systemImage: "viewfinder")
                    }
                }
            }

            if !linkedItems.isEmpty {
                Section("Linked notes and recordings") {
                    ForEach(linkedItems, id: \.id) { linkedItem in
                        NavigationLink {
                            CaptureDetailView(item: linkedItem)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: linkedItem.kind.symbol)
                                    .foregroundStyle(linkedItem.kind == .voice ? .indigo : .mint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(linkedItem.title)
                                    Text(linkedItem.previewText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button("Delete capture", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(item.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this capture?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for linkedItem in linkedItems {
                    if let fileName = linkedItem.assetFileName {
                        LocalFileStore.remove(fileName: fileName)
                    }
                    modelContext.delete(linkedItem)
                }
                if let fileName = item.assetFileName {
                    LocalFileStore.remove(fileName: fileName)
                }
                modelContext.delete(item)
                dismiss()
            }
        } message: {
            Text("The local file and its extracted text will be removed from this iPhone.")
        }
    }

    private var localImage: UIImage? {
        guard let fileName = item.assetFileName, let url = LocalFileStore.url(for: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var linkedItems: [CaptureItem] {
        allItems.filter { $0.parentCaptureID == item.id }
    }

    private var parentItem: CaptureItem? {
        guard let parentCaptureID = item.parentCaptureID else { return nil }
        return allItems.first { $0.id == parentCaptureID }
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
