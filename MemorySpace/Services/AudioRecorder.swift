import AVFoundation
import Foundation

struct RecordedAudio {
    let url: URL
    let duration: TimeInterval
}

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var timer: Timer?

    func start() async {
        errorMessage = nil
        guard await requestPermission() else {
            errorMessage = "Microphone access is needed to record a voice note."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let url = try LocalFileStore.newAudioURL()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            startedAt = .now
            elapsed = 0
            isRecording = true
            startTimer()
        } catch {
            errorMessage = "Recording could not start: \(error.localizedDescription)"
        }
    }

    func stop() -> RecordedAudio? {
        guard let recorder else { return nil }
        recorder.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        let recording = RecordedAudio(url: recorder.url, duration: recorder.currentTime)
        self.recorder = nil
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        return recording
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let startedAt else { return }
            self.elapsed = Date().timeIntervalSince(startedAt)
        }
    }
}
