import Foundation
import Speech

enum SpeechTranscriber {
    static func transcribeLocally(url: URL) async -> String? {
        guard await requestAuthorization() else { return nil }

        let recognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent)
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            let gate = TranscriptionGate(continuation: continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    gate.finish(with: result.bestTranscription.formattedString)
                } else if error != nil {
                    gate.finish(with: nil)
                }
            }
        }
    }

    private static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}

private final class TranscriptionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func finish(with text: String?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: text)
    }
}
