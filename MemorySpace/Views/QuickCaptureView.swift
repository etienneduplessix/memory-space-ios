import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var recorder = AudioRecorder()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var showsNoteEditor = false
    @State private var showsScreenshotHelp = false
    @AppStorage("importLatestScreenshotRequested") private var importLatestScreenshotRequested = false
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var captures: [CaptureItem]
    @State private var activeScreenshotID: UUID?
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "sparkles")
                    .font(.system(size: 72))
                    .foregroundStyle(recorder.isRecording ? .red : .indigo)
                    .symbolEffect(.pulse, isActive: recorder.isRecording)

                VStack(spacing: 6) {
                    Text(recorder.isRecording ? "Recording locally" : "Quick Capture")
                        .font(.title2.bold())
                    Text(recorder.isRecording ? timeString(recorder.elapsed) : "Nothing leaves your iPhone.")
                        .foregroundStyle(.secondary)
                }

                if let activeScreenshot {
                    activeScreenshotCard(activeScreenshot)
                }

                Button {
                    Task {
                        if recorder.isRecording {
                            if let recording = recorder.stop() {
                                await saveVoice(recording)
                            }
                        } else {
                            await recorder.start()
                        }
                    }
                } label: {
                    Label(
                        recorder.isRecording ? "Stop and save" : activeScreenshotID == nil ? "Record a thought" : "Add voice note to screenshot",
                        systemImage: recorder.isRecording ? "stop.fill" : "mic.fill"
                    )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .indigo)
                .disabled(isSaving)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button {
                        showsScreenshotHelp = true
                    } label: {
                        Label("Screenshot", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || recorder.isRecording)

                    Button {
                        showsNoteEditor = true
                    } label: {
                        Label(activeScreenshotID == nil ? "Write note" : "Add note", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || recorder.isRecording)

                    Button {
                        showsCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || recorder.isRecording)

                    Button {
                        showsPhotoPicker = true
                    } label: {
                        Label("Import", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || recorder.isRecording)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let errorMessage = recorder.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .photosPicker(isPresented: $showsPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task {
                    guard let data = try? await newValue.loadTransferable(type: Data.self) else {
                        message = "The selected image could not be read."
                        return
                    }
                    _ = await saveImage(data)
                    selectedPhoto = nil
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { imageData in
                    Task {
                        _ = await saveImage(imageData)
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsNoteEditor) {
                QuickNoteView(parentCaptureID: activeScreenshotID)
            }
            .sheet(isPresented: $showsScreenshotHelp) {
                ScreenshotShortcutHelpView()
            }
            .task {
                await importLatestScreenshotIfRequested()
            }
        }
    }

    private var activeScreenshot: CaptureItem? {
        guard let activeScreenshotID else { return nil }
        return captures.first { $0.id == activeScreenshotID }
    }

    @ViewBuilder
    private func activeScreenshotCard(_ screenshot: CaptureItem) -> some View {
        HStack(spacing: 12) {
            if let preview = localImage(for: screenshot) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "viewfinder")
                    .font(.title2)
                    .frame(width: 58, height: 58)
                    .background(.indigo.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshot linked")
                    .font(.headline)
                Text("Your next note or voice transcript will be attached to this screenshot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func saveVoice(_ recording: RecordedAudio) async {
        isSaving = true
        message = "Creating a local transcript…"

        let item = CaptureItem(
            kind: .voice,
            title: "Voice note",
            assetFileName: recording.url.lastPathComponent,
            durationSeconds: recording.duration,
            isProcessing: true,
            parentCaptureID: activeScreenshotID
        )
        modelContext.insert(item)
        try? modelContext.save()

        let transcription = await LocalSpeechTranscriber.transcribeLocally(url: recording.url)
        switch transcription {
        case .success(let transcript):
            item.bodyText = transcript
            item.transcriptionNotice = nil
            item.title = CaptureItem.suggestedTitle(from: transcript, fallback: "Voice note")
            item.tagsText = CaptureItem.suggestedTags(from: transcript).joined(separator: ", ")
            message = activeScreenshotID == nil
                ? "Voice note and local transcript saved."
                : "Voice note and local transcript linked to the screenshot."
        case .unavailable(let explanation):
            item.bodyText = ""
            item.transcriptionNotice = explanation
            message = activeScreenshotID == nil
                ? "Voice note saved. \(explanation)"
                : "Voice note linked to the screenshot. \(explanation)"
        }
        item.isProcessing = false
        try? modelContext.save()

        isSaving = false
    }

    @MainActor
    private func saveImage(_ imageData: Data, fallbackTitle: String = "Photo capture") async -> UUID? {
        isSaving = true
        message = "Extracting text on this iPhone…"

        do {
            let fileName = try LocalFileStore.save(data: imageData, fileExtension: "image")
            let item = CaptureItem(
                kind: .image,
                title: fallbackTitle,
                assetFileName: fileName,
                isProcessing: true
            )
            modelContext.insert(item)
            try modelContext.save()

            let extractedText = await TextExtractor.extractText(from: imageData)
            item.bodyText = extractedText
            item.title = CaptureItem.suggestedTitle(from: extractedText, fallback: fallbackTitle)
            item.tagsText = CaptureItem.suggestedTags(from: extractedText).joined(separator: ", ")
            item.isProcessing = false
            try modelContext.save()
            message = extractedText.isEmpty ? "Photo saved locally." : "Photo and extracted text saved locally."
            isSaving = false
            return item.id
        } catch {
            message = "The photo could not be saved: \(error.localizedDescription)"
            isSaving = false
            return nil
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @MainActor
    private func importLatestScreenshotIfRequested() async {
        guard importLatestScreenshotRequested else { return }
        importLatestScreenshotRequested = false
        isSaving = true
        message = "Importing the latest screenshot locally…"

        do {
            let imageData = try await LatestScreenshotImporter.loadLatestScreenshot()
            if let screenshotID = await saveImage(imageData, fallbackTitle: "Screenshot") {
                activeScreenshotID = screenshotID
                message = "Screenshot ready. Add a note or voice recording below — it will stay linked."
            }
        } catch {
            message = error.localizedDescription
            isSaving = false
        }
    }

    private func localImage(for item: CaptureItem) -> UIImage? {
        guard let fileName = item.assetFileName, let url = LocalFileStore.url(for: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct QuickNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var noteText = ""
    let parentCaptureID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextEditor(text: $noteText)
                    .font(.body)
                    .padding(10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if noteText.isEmpty {
                            Text("Write anything you want to remember…")
                                .foregroundStyle(.tertiary)
                                .padding(18)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding()
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveNote() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = CaptureItem(
            kind: .text,
            title: CaptureItem.suggestedTitle(from: text, fallback: "Note"),
            bodyText: text,
            tags: CaptureItem.suggestedTags(from: text),
            parentCaptureID: parentCaptureID
        )
        modelContext.insert(item)
        try? modelContext.save()
        dismiss()
    }
}

private struct ScreenshotShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Make it work like an Essential Key") {
                    Text("Create a Shortcut with these three actions. There are no variables to add:")
                    Label("Take Screenshot", systemImage: "viewfinder")
                    Label("Save to Photo Album", systemImage: "photo.on.rectangle")
                    Label("Finish Screenshot Capture", systemImage: "tray.and.arrow.down.fill")
                }

                Section("Then assign it") {
                    Text("In Settings, choose Action Button → Shortcut and select the shortcut you created. Each press captures the current screen, saves it to Photos, imports it into Memory Space, extracts text, then opens this screen so you can add a note or voice recording. On first use, choose Full Access when Memory Space asks to read Photos.")
                }
            }
            .navigationTitle("Screenshot Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
