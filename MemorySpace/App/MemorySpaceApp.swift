import SwiftData
import SwiftUI

@main
struct MemorySpaceApp: App {
    private let modelContainer: ModelContainer = {
        do {
            let schema = Schema([CaptureItem.self])
            let configuration = ModelConfiguration("MemorySpace", schema: schema)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to open the local Memory Space library: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
