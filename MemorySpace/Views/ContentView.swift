import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var showsQuickCapture = false
    @AppStorage("quickCaptureRequested") private var quickCaptureRequested = false

    var body: some View {
        TabView {
            InboxView(showsQuickCapture: $showsQuickCapture)
                .tabItem {
                    Label("Inbox", systemImage: "tray.full.fill")
                }

            CollectionsView()
                .tabItem {
                    Label("Collections", systemImage: "square.stack.3d.up.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "lock.fill")
                }
        }
        .tint(.indigo)
        .sheet(isPresented: $showsQuickCapture) {
            QuickCaptureView()
        }
        .onAppear {
            presentQuickCaptureIfRequested()
        }
        .onChange(of: quickCaptureRequested) { _, _ in
            presentQuickCaptureIfRequested()
        }
    }

    private func presentQuickCaptureIfRequested() {
        guard quickCaptureRequested else { return }
        quickCaptureRequested = false
        showsQuickCapture = true
    }
}

private struct InboxView: View {
    @Binding var showsQuickCapture: Bool
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var items: [CaptureItem]
    @State private var searchText = ""

    private var filteredItems: [CaptureItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { item in
            [item.title, item.bodyText, item.tagsText, item.collectionName]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "Your space is empty" : "Nothing found", systemImage: searchText.isEmpty ? "sparkles" : "magnifyingglass")
                    } description: {
                        Text(searchText.isEmpty ? "Capture a thought, photo, or document. It stays on this iPhone." : "Try a different word from a transcript, title, or tag.")
                    } actions: {
                        if searchText.isEmpty {
                            Button("Quick Capture") {
                                showsQuickCapture = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    List(filteredItems, id: \.id) { item in
                        NavigationLink {
                            CaptureDetailView(item: item)
                        } label: {
                            CaptureRow(item: item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Memory Space")
            .searchable(text: $searchText, prompt: "Search your phone")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsQuickCapture = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Quick Capture")
                }
            }
        }
    }
}

private struct CaptureRow: View {
    let item: CaptureItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    if item.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(item.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.collectionName)
                    Text("•")
                    Text(item.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch item.kind {
        case .voice: .indigo
        case .image: .orange
        case .text: .mint
        }
    }
}

private struct CollectionsView: View {
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var items: [CaptureItem]

    private var names: [String] {
        Array(Set(items.map(\.collectionName))).sorted { lhs, rhs in
            if lhs == "Inbox" { return true }
            if rhs == "Inbox" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if names.isEmpty {
                    ContentUnavailableView("No collections yet", systemImage: "square.stack.3d.up")
                } else {
                    ForEach(names, id: \.self) { name in
                        NavigationLink {
                            CollectionItemsView(collectionName: name)
                        } label: {
                            Label {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Text("\(items.filter { $0.collectionName == name }.count)")
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: name == "Inbox" ? "tray.full.fill" : "folder.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collections")
        }
    }
}

private struct CollectionItemsView: View {
    let collectionName: String
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var allItems: [CaptureItem]

    private var items: [CaptureItem] {
        allItems.filter { $0.collectionName == collectionName }
    }

    var body: some View {
        List(items, id: \.id) { item in
            NavigationLink {
                CaptureDetailView(item: item)
            } label: {
                CaptureRow(item: item)
            }
        }
        .navigationTitle(collectionName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Local by default") {
                    Label("No server is connected", systemImage: "iphone")
                    Label("Recordings and captures stay on this iPhone", systemImage: "lock.fill")
                    Label("Image text is extracted on-device", systemImage: "text.viewfinder")
                }

                Section("Integrations") {
                    Label("Quick Capture is available in Shortcuts and for the Action Button", systemImage: "button.programmable")
                }

                Section("Coming next") {
                    Label("Face ID app lock", systemImage: "faceid")
                    Label("Optional encrypted backup", systemImage: "icloud")
                }
            }
            .navigationTitle("Privacy")
        }
    }
}
