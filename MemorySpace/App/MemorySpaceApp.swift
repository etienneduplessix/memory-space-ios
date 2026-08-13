import SwiftData
import SwiftUI

@main
struct MemorySpaceApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try MemorySpaceStore.makeContainer()
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
