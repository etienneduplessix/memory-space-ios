import SwiftData
import SwiftUI
import UIKit

struct CaptureDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                TextEditor(text: $item.bodyText)
                    .frame(minHeight: 180)
            }

            Section("Tags") {
                TextField("receipt, idea, meeting", text: $item.tagsText)
                    .textInputAutocapitalization(.never)
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

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
