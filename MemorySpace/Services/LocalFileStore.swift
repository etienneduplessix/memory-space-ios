import Foundation

enum LocalFileStore {
    private static let directoryName = "Captures"

    static func save(data: Data, fileExtension: String) throws -> String {
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let url = try capturesDirectory().appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        return fileName
    }

    static func newAudioURL() throws -> URL {
        try capturesDirectory().appendingPathComponent("\(UUID().uuidString).m4a")
    }

    static func url(for fileName: String) -> URL? {
        try? capturesDirectory().appendingPathComponent(fileName)
    }

    static func remove(fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func capturesDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
