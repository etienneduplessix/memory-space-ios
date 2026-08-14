import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var showsQuickCapture = false
    @AppStorage("quickCaptureRequested") private var quickCaptureRequested = false

    var body: some View {
        TabView {
            TimelineView(showsQuickCapture: $showsQuickCapture)
                .tabItem {
                    Label("Timeline", systemImage: "rectangle.3.group.fill")
                }

            SmartSortView()
                .tabItem {
                    Label("Smart", systemImage: "sparkles")
                }

            InboxView(showsQuickCapture: $showsQuickCapture)
                .tabItem {
                    Label("Library", systemImage: "tray.full.fill")
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

private struct TimelineView: View {
    @Binding var showsQuickCapture: Bool
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var allItems: [CaptureItem]

    private var rootItems: [CaptureItem] {
        allItems.filter { $0.parentCaptureID == nil }
    }

    private var dayGroups: [TimelineDay] {
        let calendar = Calendar.current
        let groupedItems = Dictionary(grouping: rootItems) { item in
            calendar.startOfDay(for: item.createdAt)
        }

        return groupedItems
            .map { TimelineDay(date: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if dayGroups.isEmpty {
                    ContentUnavailableView {
                        Label("Your timeline is empty", systemImage: "rectangle.3.group")
                    } description: {
                        Text("Use Quick Capture to save a screenshot, then add a note or voice recording. It will appear here as one block.")
                    } actions: {
                        Button("Quick Capture") {
                            showsQuickCapture = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            Text("New captures appear here automatically. Screenshots keep their notes and voice transcripts together.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)

                            ForEach(dayGroups) { day in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(day.title)
                                        .font(.title3.bold())
                                        .padding(.horizontal, 20)

                                    ForEach(day.items, id: \.id) { item in
                                        NavigationLink {
                                            CaptureDetailView(item: item)
                                        } label: {
                                            TimelineCaptureBlock(
                                                item: item,
                                                linkedItems: allItems.filter { $0.parentCaptureID == item.id }
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Timeline")
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

private struct TimelineDay: Identifiable {
    let date: Date
    let items: [CaptureItem]

    var id: Date { date }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .complete, time: .omitted)
    }
}

private struct TimelineCaptureBlock: View {
    let item: CaptureItem
    let linkedItems: [CaptureItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(item.kind == .image ? "Screenshot or image" : item.kind.title, systemImage: item.kind.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Spacer()
                Text(item.createdAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.kind == .image, let image = localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 164)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            if item.kind != .image, !item.previewText.isEmpty {
                Text(item.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if linkedItems.isEmpty, item.kind == .image {
                Label("No linked note yet — add one from Quick Capture.", systemImage: "plus.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !linkedItems.isEmpty {
                Divider()

                Text("Linked to this capture")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(linkedItems, id: \.id) { linkedItem in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: linkedItem.kind.symbol)
                            .foregroundStyle(linkedItem.kind == .voice ? .indigo : .mint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(linkedItem.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(linkedItem.previewText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var accentColor: Color {
        switch item.kind {
        case .voice: .indigo
        case .image: .orange
        case .text: .mint
        }
    }

    private var localImage: UIImage? {
        guard let fileName = item.assetFileName, let url = LocalFileStore.url(for: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct SmartSortView: View {
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var allItems: [CaptureItem]

    private var rootItems: [CaptureItem] {
        allItems.filter { $0.parentCaptureID == nil }
    }

    private var topicGroups: [(topic: SmartTopic, items: [CaptureItem])] {
        SmartTopic.allCases.compactMap { topic in
            let items = rootItems.filter { item in
                SmartSortClassifier.topic(for: item, linkedItems: linkedItems(for: item)) == topic
            }
            return items.isEmpty ? nil : (topic, items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if topicGroups.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to sort yet", systemImage: "sparkles")
                    } description: {
                        Text("Your screenshots, notes, and voice transcripts will be grouped here automatically after you capture them.")
                    }
                } else {
                    List {
                        Section {
                            Text("Smart sorting reads only the text already stored on this iPhone. A screenshot and its linked note or transcript are understood as one capture.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(topicGroups, id: \.topic) { group in
                            Section {
                                ForEach(group.items, id: \.id) { item in
                                    NavigationLink {
                                        CaptureDetailView(item: item)
                                    } label: {
                                        CaptureRow(item: item)
                                    }
                                }
                            } header: {
                                Label("\(group.topic.title) (\(group.items.count))", systemImage: group.topic.symbol)
                                    .foregroundStyle(group.topic.color)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Smart Sort")
        }
    }

    private func linkedItems(for item: CaptureItem) -> [CaptureItem] {
        allItems.filter { $0.parentCaptureID == item.id }
    }
}

private enum SmartTopic: String, CaseIterable, Identifiable {
    case action
    case work
    case money
    case idea
    case place
    case reference
    case personal
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .action: "Actions"
        case .work: "Work"
        case .money: "Money"
        case .idea: "Ideas"
        case .place: "Places"
        case .reference: "Reference"
        case .personal: "Personal"
        case .other: "Everything else"
        }
    }

    var symbol: String {
        switch self {
        case .action: "checklist"
        case .work: "briefcase.fill"
        case .money: "eurosign.circle.fill"
        case .idea: "lightbulb.fill"
        case .place: "mappin.and.ellipse"
        case .reference: "bookmark.fill"
        case .personal: "heart.fill"
        case .other: "square.stack.3d.up"
        }
    }

    var color: Color {
        switch self {
        case .action: .orange
        case .work: .indigo
        case .money: .green
        case .idea: .yellow
        case .place: .teal
        case .reference: .blue
        case .personal: .pink
        case .other: .secondary
        }
    }

    var keywords: [String] {
        switch self {
        case .action:
            ["todo", "to do", "remind", "reminder", "need to", "must", "call ", "email ", "send ", "buy ", "deadline", "tomorrow", "next week"]
        case .work:
            ["meeting", "agenda", "project", "client", "team", "presentation", "work", "proposal", "contract"]
        case .money:
            ["€", "eur", "receipt", "total", "price", "invoice", "payment", "bill", "order", "tax"]
        case .idea:
            ["idea", "concept", "brainstorm", "maybe", "could", "feature", "design", "inspiration"]
        case .place:
            ["address", "prague", "restaurant", "hotel", "flight", "train", "airport", "map", "location"]
        case .reference:
            ["http://", "https://", "www.", "article", "read later", "watch", "book", "podcast", "quote"]
        case .personal:
            ["family", "birthday", "health", "doctor", "home", "friend", "holiday"]
        case .other:
            []
        }
    }
}

private enum SmartSortClassifier {
    static func topic(for item: CaptureItem, linkedItems: [CaptureItem]) -> SmartTopic {
        let text = ([item.title, item.bodyText, item.tagsText] + linkedItems.flatMap { [$0.title, $0.bodyText, $0.tagsText] })
            .joined(separator: " ")
            .lowercased()

        let scoredTopics = SmartTopic.allCases.dropLast().map { topic in
            (topic, topic.keywords.reduce(into: 0) { score, keyword in
                if text.contains(keyword) { score += 1 }
            })
        }

        guard let bestMatch = scoredTopics.max(by: { lhs, rhs in lhs.1 < rhs.1 }), bestMatch.1 > 0 else {
            return .other
        }

        return bestMatch.0
    }
}

private struct InboxView: View {
    @Binding var showsQuickCapture: Bool
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var items: [CaptureItem]
    @State private var searchText = ""

    private var filteredItems: [CaptureItem] {
        let rootItems = items.filter { $0.parentCaptureID == nil }
        guard !searchText.isEmpty else { return rootItems }
        return rootItems.filter { item in
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
        Array(Set(rootItems.map(\.collectionName))).sorted { lhs, rhs in
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
                                    Text("\(rootItems.filter { $0.collectionName == name }.count)")
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

    private var rootItems: [CaptureItem] {
        items.filter { $0.parentCaptureID == nil }
    }
}

private struct CollectionItemsView: View {
    let collectionName: String
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var allItems: [CaptureItem]

    private var items: [CaptureItem] {
        allItems.filter { $0.collectionName == collectionName && $0.parentCaptureID == nil }
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
