import SwiftData

enum MemorySpaceStore {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([CaptureItem.self])
        let configuration = ModelConfiguration("MemorySpace", schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
