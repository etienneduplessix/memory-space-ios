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
                    Label(recorder.isRecording ? "Stop and save" : "Record a thought", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .indigo)
                .disabled(isSaving)

                HStack(spacing: 12) {
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
                    await saveImage(data)
                    selectedPhoto = nil
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { imageData in
                    Task {
                        await saveImage(imageData)
                    }
                }
                .ignoresSafeArea()
            }
        }
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
            isProcessing: true
        )
        modelContext.insert(item)
        try? modelContext.save()

        let transcript = await SpeechTranscriber.transcribeLocally(url: recording.url) ?? ""
        item.bodyText = transcript
        item.title = CaptureItem.suggestedTitle(from: transcript, fallback: "Voice note")
        item.tagsText = CaptureItem.suggestedTags(from: transcript).joined(separator: ", ")
        item.isProcessing = false
        try? modelContext.save()

        isSaving = false
        message = transcript.isEmpty
            ? "Saved locally. A local transcript is not available for the current language."
            : "Voice note saved locally."
    }

    @MainActor
    private func saveImage(_ imageData: Data) async {
        isSaving = true
        message = "Extracting text on this iPhone…"

        do {
            let fileName = try LocalFileStore.save(data: imageData, fileExtension: "image")
            let item = CaptureItem(
                kind: .image,
                title: "Photo capture",
                assetFileName: fileName,
                isProcessing: true
            )
            modelContext.insert(item)
            try modelContext.save()

            let extractedText = await TextExtractor.extractText(from: imageData)
            item.bodyText = extractedText
            item.title = CaptureItem.suggestedTitle(from: extractedText, fallback: "Photo capture")
            item.tagsText = CaptureItem.suggestedTags(from: extractedText).joined(separator: ", ")
            item.isProcessing = false
            try modelContext.save()
            message = extractedText.isEmpty ? "Photo saved locally." : "Photo and extracted text saved locally."
        } catch {
            message = "The photo could not be saved: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
