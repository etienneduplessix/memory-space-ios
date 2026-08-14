import Foundation
import SwiftData
import UIKit

enum MemorySpaceStore {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([CaptureItem.self])
        let configuration = ModelConfiguration("MemorySpace", schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

struct MacSyncResponse: Decodable {
    let receivedCaptures: Int
    let updatedAt: Date
}

enum MacSyncError: LocalizedError {
    case invalidEndpoint
    case missingPairingToken
    case unexpectedResponse
    case bridgeRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Enter the Mac bridge address, for example http://192.168.1.20:8787."
        case .missingPairingToken:
            "Enter the pairing token shown by the Mac bridge."
        case .unexpectedResponse:
            "The Mac bridge returned an unexpected response."
        case .bridgeRejected(let message):
            message
        }
    }
}

enum MacSyncService {
    @MainActor
    static func sync(
        captures: [CaptureItem],
        endpointText: String,
        pairingToken: String
    ) async throws -> MacSyncResponse {
        let endpoint = try syncEndpoint(from: endpointText)
        let token = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MacSyncError.missingPairingToken }

        let payload = MacSyncPayload(
            deviceName: UIDevice.current.name,
            sentAt: .now,
            captures: captures.map(MacSyncCapture.init),
            customBlocksData: UserDefaults.standard.data(forKey: "customSmartBlocksData")?.base64EncodedString()
        )

        var request = URLRequest(url: endpoint.appendingPathComponent("v1/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacSyncError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bridgeError = (try? JSONDecoder().decode(MacSyncBridgeError.self, from: data).error)
            throw MacSyncError.bridgeRejected(bridgeError ?? "Mac bridge rejected the sync (HTTP \(httpResponse.statusCode)).")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let result = try? decoder.decode(MacSyncResponse.self, from: data) else {
            throw MacSyncError.unexpectedResponse
        }
        return result
    }

    @MainActor
    static func testConnection(endpointText: String) async throws {
        let endpoint = try syncEndpoint(from: endpointText)
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/health"))
        request.timeoutInterval = 8
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw MacSyncError.bridgeRejected("Memory Space Bridge could not be reached.")
        }
    }

    private static func syncEndpoint(from endpointText: String) throws -> URL {
        let trimmed = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw MacSyncError.invalidEndpoint
        }
        return url
    }
}

private struct MacSyncPayload: Encodable {
    let deviceName: String
    let sentAt: Date
    let captures: [MacSyncCapture]
    let customBlocksData: String?
}

private struct MacSyncCapture: Encodable {
    let id: String
    let createdAt: Date
    let kind: String
    let title: String
    let bodyText: String
    let tagsText: String
    let collectionName: String
    let parentCaptureID: String?
    let durationSeconds: Double
    let isProcessing: Bool
    let transcriptionNotice: String?
    let imageBase64: String?

    @MainActor
    init(item: CaptureItem) {
        id = item.id.uuidString
        createdAt = item.createdAt
        kind = item.kind.rawValue
        title = item.title
        bodyText = item.bodyText
        tagsText = item.tagsText
        collectionName = item.collectionName
        parentCaptureID = item.parentCaptureID?.uuidString
        durationSeconds = item.durationSeconds
        isProcessing = item.isProcessing
        transcriptionNotice = item.transcriptionNotice
        imageBase64 = Self.compressedImageData(for: item)?.base64EncodedString()
    }

    @MainActor
    private static func compressedImageData(for item: CaptureItem) -> Data? {
        guard item.kind == .image,
              let fileName = item.assetFileName,
              let url = LocalFileStore.url(for: fileName),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }

        let maximumDimension: CGFloat = 1_600
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedImage.jpegData(compressionQuality: 0.78)
    }
}

private struct MacSyncBridgeError: Decodable {
    let error: String
}
