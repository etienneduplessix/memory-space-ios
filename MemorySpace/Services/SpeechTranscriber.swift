import AVFoundation
import Foundation
import Speech

enum LocalTranscriptionResult {
    case success(String)
    case unavailable(String)
}

enum LocalSpeechTranscriber {
    static func transcribeLocally(url: URL) async -> LocalTranscriptionResult {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            return .unavailable(authorizationMessage(for: authorization))
        }

        if #available(iOS 26.0, *) {
            return await transcribeWithOnDeviceAnalyzer(url: url)
        }

        return await transcribeWithLegacyOnDeviceRecognizer(url: url)
    }

    @available(iOS 26.0, *)
    private static func transcribeWithOnDeviceAnalyzer(url: URL) async -> LocalTranscriptionResult {
        let requestedLocale = selectedLocale()

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            return .unavailable("On-device transcription is not available for \(requestedLocale.localizedString(forIdentifier: requestedLocale.identifier) ?? requestedLocale.identifier).")
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let modules: [any SpeechModule] = [transcriber]

        do {
            let status = await AssetInventory.status(forModules: modules)
            guard status != .unsupported else {
                return .unavailable("This iPhone does not provide an on-device speech model for \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).")
            }

            if status != .installed,
               let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                // This downloads Apple's language model only. Your recordings remain on the iPhone.
                try await request.downloadAndInstall()
            }

            guard await AssetInventory.status(forModules: modules) == .installed else {
                return .unavailable("The on-device speech model is still downloading. Keep this app open and try the recording again in a moment.")
            }

            let audioFile = try AVAudioFile(forReading: url)
            let analyzer = SpeechAnalyzer(modules: modules)
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

            var transcript: AttributedString = ""
            for try await result in transcriber.results {
                transcript += result.text
            }

            let text = String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return .unavailable("No speech was recognised. Try a longer recording in a quieter place.")
            }
            return .success(text)
        } catch {
            return .unavailable("Local transcription could not finish: \(error.localizedDescription)")
        }
    }

    private static func transcribeWithLegacyOnDeviceRecognizer(url: URL) async -> LocalTranscriptionResult {
        let recognizer = SFSpeechRecognizer(locale: selectedLocale())
        guard let recognizer else {
            return .unavailable("Speech recognition is unavailable for the selected iPhone language.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable("This iPhone has no offline speech model for the selected language. The app will not send your recording to a server.")
        }
        guard recognizer.isAvailable else {
            return .unavailable("On-device speech recognition is temporarily unavailable. Please try again.")
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            let gate = LegacyTranscriptionGate(continuation: continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    gate.finish(with: text.isEmpty ? .unavailable("No speech was recognised. Try a longer recording in a quieter place.") : .success(text))
                } else if let error {
                    gate.finish(with: .unavailable("Local transcription could not finish: \(error.localizedDescription)"))
                }
            }
        }
    }

    private static func selectedLocale() -> Locale {
        let identifier = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        return Locale(identifier: identifier)
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func authorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            "Speech Recognition is off. Enable it in Settings → Apps → Memory Space → Speech Recognition, then record again."
        case .restricted:
            "Speech Recognition is restricted on this iPhone. Check Screen Time or device management restrictions."
        case .notDetermined:
            "Speech Recognition permission has not been granted yet."
        case .authorized:
            "Speech recognition is unavailable."
        @unknown default:
            "Speech recognition is unavailable."
        }
    }
}

private final class LegacyTranscriptionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LocalTranscriptionResult, Never>?

    init(continuation: CheckedContinuation<LocalTranscriptionResult, Never>) {
        self.continuation = continuation
    }

    func finish(with result: LocalTranscriptionResult) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
