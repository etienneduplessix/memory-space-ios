import CryptoKit
import Foundation
import Network

private let serviceType = "_memoryspace._tcp"
private let maximumPayloadBytes = 40 * 1024 * 1024

private struct BridgeConfiguration: Codable {
    let pairingToken: String
    let createdAt: String
}

private struct NearbyMacSyncEnvelope: Decodable {
    let nonceBase64: String
    let ciphertextBase64: String
    let tagBase64: String
}

private final class NearbyBridgeReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.etienneduplessix.memoryspace.nearby-bridge")
    private let storeDirectory: URL
    private let configurationURL: URL
    private let snapshotURL: URL
    private let attachmentsDirectory: URL
    private let configuration: BridgeConfiguration
    private var listener: NWListener?

    init() throws {
        if let overrideDirectory = ProcessInfo.processInfo.environment["MEMORY_SPACE_BRIDGE_DIR"], !overrideDirectory.isEmpty {
            storeDirectory = URL(fileURLWithPath: overrideDirectory, isDirectory: true)
        } else {
            let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            storeDirectory = libraryDirectory.appendingPathComponent("Application Support/MemorySpaceBridge", isDirectory: true)
        }
        configurationURL = storeDirectory.appendingPathComponent("configuration.json")
        snapshotURL = storeDirectory.appendingPathComponent("memory-space.json")
        attachmentsDirectory = storeDirectory.appendingPathComponent("attachments", isDirectory: true)

        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        configuration = try Self.loadOrCreateConfiguration(at: configurationURL)
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        parameters.acceptLocalOnly = true

        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(name: Host.current().localizedName ?? "Memory Space Bridge", type: serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            self?.receiveHeader(on: connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Nearby receiver is ready. Keep this Terminal window open while syncing.")
            case let .failed(error):
                fputs("Nearby receiver failed: \(error.localizedDescription)\n", stderr)
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)

        print("Memory Space Nearby Bridge")
        print("Pairing token: \(configuration.pairingToken)")
        print("On iPhone: Memory Space → Privacy → Sync to Mac → enter this token → select this Mac.")
    }

    private func receiveHeader(on connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] headerData, _, _, error in
            guard let self else { return }
            guard error == nil, let headerData, headerData.count == 8 else {
                self.reply("ERROR Could not read nearby sync header.", on: connection)
                return
            }

            let length = headerData.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard length > 0, length <= UInt64(maximumPayloadBytes) else {
                self.reply("ERROR Nearby sync payload is too large.", on: connection)
                return
            }

            self.receivePayload(on: connection, length: Int(length))
        }
    }

    private func receivePayload(on connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] payloadData, _, _, error in
            guard let self else { return }
            guard error == nil, let payloadData, payloadData.count == length else {
                self.reply("ERROR Could not read nearby sync data.", on: connection)
                return
            }

            do {
                let count = try self.persist(payloadData)
                self.reply("OK \(count)", on: connection)
                print("Received \(count) captures from your iPhone.")
            } catch {
                self.reply("ERROR \(error.localizedDescription)", on: connection)
            }
        }
    }

    private func persist(_ envelopeData: Data) throws -> Int {
        let envelope = try JSONDecoder().decode(NearbyMacSyncEnvelope.self, from: envelopeData)
        guard let nonce = Data(base64Encoded: envelope.nonceBase64),
              let ciphertext = Data(base64Encoded: envelope.ciphertextBase64),
              let tag = Data(base64Encoded: envelope.tagBase64) else {
            throw NSError(domain: "MemorySpaceNearbyBridge", code: 400, userInfo: [NSLocalizedDescriptionKey: "The nearby sync payload is not valid."])
        }

        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(configuration.pairingToken.utf8))))
        let payloadData: Data
        do {
            let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            payloadData = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw NSError(
                domain: "MemorySpaceNearbyBridge",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Pairing token does not match. Copy the current token from the Mac receiver into Memory Space, then try again."]
            )
        }

        guard let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let rawCaptures = payload["captures"] as? [[String: Any]] else {
            throw NSError(domain: "MemorySpaceNearbyBridge", code: 400, userInfo: [NSLocalizedDescriptionKey: "The nearby sync payload is not valid."])
        }

        var captures: [[String: Any]] = []
        for rawCapture in rawCaptures {
            guard let id = rawCapture["id"] as? String, !id.isEmpty else { continue }
            var capture = rawCapture
            capture.removeValue(forKey: "imageBase64")
            capture["imagePath"] = NSNull()

            if let imageBase64 = rawCapture["imageBase64"] as? String,
               let imageData = Data(base64Encoded: imageBase64),
               !imageData.isEmpty,
               imageData.count <= 8 * 1024 * 1024 {
                let fileName = "\(id).jpg"
                try imageData.write(to: attachmentsDirectory.appendingPathComponent(fileName), options: .atomic)
                capture["imagePath"] = "attachments/\(fileName)"
            }
            captures.append(capture)
        }

        let snapshot: [String: Any] = [
            "schemaVersion": 1,
            "deviceName": payload["deviceName"] as? String ?? "iPhone",
            "updatedAt": ISO8601DateFormatter().string(from: .now),
            "captures": captures,
            "customBlocks": customBlocks(from: payload["customBlocksData"])
        ]
        let snapshotData = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        try snapshotData.write(to: snapshotURL, options: .atomic)
        return captures.count
    }

    private func customBlocks(from encodedBlocks: Any?) -> Any {
        guard let encodedBlocks = encodedBlocks as? String,
              let blockData = Data(base64Encoded: encodedBlocks),
              let blocks = try? JSONSerialization.jsonObject(with: blockData) else {
            return []
        }
        return blocks
    }

    private func reply(_ message: String, on connection: NWConnection) {
        connection.send(content: Data(message.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func loadOrCreateConfiguration(at url: URL) throws -> BridgeConfiguration {
        if FileManager.default.fileExists(atPath: url.path) {
            return try JSONDecoder().decode(BridgeConfiguration.self, from: Data(contentsOf: url))
        }

        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        let configuration = BridgeConfiguration(pairingToken: token, createdAt: ISO8601DateFormatter().string(from: .now))
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: url, options: .atomic)
        return configuration
    }
}

do {
    let receiver = try NearbyBridgeReceiver()
    try receiver.start()
    dispatchMain()
} catch {
    fputs("Could not start Memory Space Nearby Bridge: \(error.localizedDescription)\n", stderr)
    exit(1)
}
