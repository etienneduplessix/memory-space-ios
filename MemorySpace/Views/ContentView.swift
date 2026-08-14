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
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()

    private var rootItems: [CaptureItem] {
        allItems.filter { $0.parentCaptureID == nil && !$0.isArchived }
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
                                    HStack {
                                        Text(day.title)
                                            .font(.title3.bold())
                                        Spacer()
                                        if isSelecting {
                                            Button(isDayFullySelected(day) ? "Deselect day" : "Select day") {
                                                toggleDaySelection(day)
                                            }
                                            .font(.caption.weight(.semibold))
                                        }
                                    }
                                    .padding(.horizontal, 20)

                                    ForEach(day.items, id: \.id) { item in
                                        if isSelecting {
                                            Button {
                                                toggleSelection(for: item)
                                            } label: {
                                                HStack(alignment: .top, spacing: 10) {
                                                    CaptureSelectionIndicator(isSelected: selectedIDs.contains(item.id))
                                                        .padding(.top, 14)
                                                    TimelineCaptureBlock(
                                                        item: item,
                                                        linkedItems: allItems.filter { $0.parentCaptureID == item.id }
                                                    )
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.horizontal, 16)
                                        } else {
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
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !dayGroups.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(areAllRootItemsSelected ? "Clear" : "All") {
                            if areAllRootItemsSelected {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(rootItems.map(\.id))
                            }
                        }
                    } else {
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    CaptureBulkActionBar(
                        selectedIDs: $selectedIDs,
                        isSelecting: $isSelecting,
                        allItems: allItems,
                        mode: .active
                    )
                }
            }
        }
    }

    private func toggleSelection(for item: CaptureItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private var areAllRootItemsSelected: Bool {
        !rootItems.isEmpty && Set(rootItems.map(\.id)).isSubset(of: selectedIDs)
    }

    private func isDayFullySelected(_ day: TimelineDay) -> Bool {
        Set(day.items.map(\.id)).isSubset(of: selectedIDs)
    }

    private func toggleDaySelection(_ day: TimelineDay) {
        let dayIDs = Set(day.items.map(\.id))
        if dayIDs.isSubset(of: selectedIDs) {
            selectedIDs.subtract(dayIDs)
        } else {
            selectedIDs.formUnion(dayIDs)
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
    @AppStorage("customSmartBlocksData") private var customBlocksData = Data()
    @State private var showsNewBlock = false

    private var rootItems: [CaptureItem] {
        allItems.filter { $0.parentCaptureID == nil && !$0.isArchived }
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
                if topicGroups.isEmpty && customBlocks.isEmpty {
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

                        if !customBlocks.isEmpty {
                            Section("My blocks") {
                                Text("Matching captures appear in these blocks automatically.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(customBlocks) { block in
                                let matchedItems = rootItems.filter { item in
                                    block.matches(item: item, linkedItems: linkedItems(for: item))
                                }

                                Section {
                                    if matchedItems.isEmpty {
                                        Label("Waiting for a matching capture", systemImage: "hourglass")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(matchedItems, id: \.id) { item in
                                            NavigationLink {
                                                CaptureDetailView(item: item)
                                            } label: {
                                                CaptureRow(item: item)
                                            }
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Label(block.title, systemImage: "square.stack.3d.up.fill")
                                            .foregroundStyle(.indigo)
                                        Spacer()
                                        Button("Delete", role: .destructive) {
                                            delete(block)
                                        }
                                        .textCase(nil)
                                        .font(.caption)
                                    }
                                } footer: {
                                    Text(block.keywordsText)
                                }
                            }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsNewBlock = true
                    } label: {
                        Label("Create block", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showsNewBlock) {
                CreateSmartBlockView { block in
                    save(block)
                }
            }
        }
    }

    private func linkedItems(for item: CaptureItem) -> [CaptureItem] {
        allItems.filter { $0.parentCaptureID == item.id }
    }

    private var customBlocks: [CustomSmartBlock] {
        guard !customBlocksData.isEmpty,
              let blocks = try? JSONDecoder().decode([CustomSmartBlock].self, from: customBlocksData) else {
            return []
        }
        return blocks.sorted { $0.createdAt < $1.createdAt }
    }

    private func save(_ block: CustomSmartBlock) {
        var blocks = customBlocks
        blocks.append(block)
        customBlocksData = (try? JSONEncoder().encode(blocks)) ?? customBlocksData
    }

    private func delete(_ block: CustomSmartBlock) {
        let blocks = customBlocks.filter { $0.id != block.id }
        customBlocksData = (try? JSONEncoder().encode(blocks)) ?? customBlocksData
    }
}

struct CustomSmartBlock: Codable, Identifiable {
    let id: UUID
    let title: String
    let keywordsText: String
    let createdAt: Date
    var manualCaptureIDs: [UUID]

    init(title: String, keywordsText: String, manualCaptureIDs: [UUID] = []) {
        self.id = UUID()
        self.title = title
        self.keywordsText = keywordsText
        self.createdAt = .now
        self.manualCaptureIDs = manualCaptureIDs
    }

    func matches(item: CaptureItem, linkedItems: [CaptureItem]) -> Bool {
        if manualCaptureIDs.contains(item.id) {
            return true
        }

        let text = ([item.title, item.bodyText, item.tagsText] + linkedItems.flatMap { [$0.title, $0.bodyText, $0.tagsText] })
            .joined(separator: " ")
            .lowercased()

        return matchingTerms.contains { text.contains($0) }
    }

    func including(_ captureIDs: Set<UUID>) -> CustomSmartBlock {
        var updated = self
        updated.manualCaptureIDs = Array(Set(manualCaptureIDs).union(captureIDs)).sorted { $0.uuidString < $1.uuidString }
        return updated
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case keywordsText
        case createdAt
        case manualCaptureIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        keywordsText = try container.decode(String.self, forKey: .keywordsText)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        manualCaptureIDs = try container.decodeIfPresent([UUID].self, forKey: .manualCaptureIDs) ?? []
    }

    private var matchingTerms: [String] {
        let keywords = keywordsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let titleWords = title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 }
            .map { $0.lowercased() }

        return Array(Set(keywords + titleWords)).filter { !$0.isEmpty }
    }
}

private struct CreateSmartBlockView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var keywords = ""
    let onSave: (CustomSmartBlock) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Block") {
                    TextField("Name, for example Waard ideas", text: $title)
                }

                Section("What belongs in it?") {
                    TextEditor(text: $keywords)
                        .frame(minHeight: 110)
                    Text("Add words or short phrases separated by commas. The block name is also used automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Example") {
                    Text("For “Waard ideas”, add: wand, dragon, spell, gameplay, AR")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(CustomSmartBlock(title: title.trimmingCharacters(in: .whitespacesAndNewlines), keywordsText: keywords))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()

    private var filteredItems: [CaptureItem] {
        let rootItems = items.filter { $0.parentCaptureID == nil && !$0.isArchived }
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
                        if isSelecting {
                            Button {
                                toggleSelection(for: item)
                            } label: {
                                HStack(spacing: 10) {
                                    CaptureSelectionIndicator(isSelected: selectedIDs.contains(item.id))
                                    CaptureRow(item: item)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                CaptureDetailView(item: item)
                            } label: {
                                CaptureRow(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Memory Space")
            .searchable(text: $searchText, prompt: "Search your phone")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !filteredItems.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !archivedItems.isEmpty {
                        NavigationLink {
                            ArchivedItemsView()
                        } label: {
                            Image(systemName: "archivebox")
                        }
                        .accessibilityLabel("Archived captures")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(areAllFilteredItemsSelected ? "Clear" : "All") {
                            if areAllFilteredItemsSelected {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(filteredItems.map(\.id))
                            }
                        }
                    } else {
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    CaptureBulkActionBar(
                        selectedIDs: $selectedIDs,
                        isSelecting: $isSelecting,
                        allItems: items,
                        mode: .active
                    )
                }
            }
        }
    }

    private var archivedItems: [CaptureItem] {
        items.filter { $0.parentCaptureID == nil && $0.isArchived }
    }

    private var areAllFilteredItemsSelected: Bool {
        !filteredItems.isEmpty && Set(filteredItems.map(\.id)).isSubset(of: selectedIDs)
    }

    private func toggleSelection(for item: CaptureItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
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
        items.filter { $0.parentCaptureID == nil && !$0.isArchived }
    }
}

private struct CollectionItemsView: View {
    let collectionName: String
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var allItems: [CaptureItem]
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()

    private var items: [CaptureItem] {
        allItems.filter { $0.collectionName == collectionName && $0.parentCaptureID == nil && !$0.isArchived }
    }

    var body: some View {
        List(items, id: \.id) { item in
            if isSelecting {
                Button {
                    toggleSelection(for: item)
                } label: {
                    HStack(spacing: 10) {
                        CaptureSelectionIndicator(isSelected: selectedIDs.contains(item.id))
                        CaptureRow(item: item)
                    }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    CaptureDetailView(item: item)
                } label: {
                    CaptureRow(item: item)
                }
            }
        }
        .navigationTitle(collectionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button(areAllItemsSelected ? "Clear" : "All") {
                        if areAllItemsSelected {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(items.map(\.id))
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                CaptureBulkActionBar(
                    selectedIDs: $selectedIDs,
                    isSelecting: $isSelecting,
                    allItems: allItems,
                    mode: .active
                )
            }
        }
    }

    private func toggleSelection(for item: CaptureItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private var areAllItemsSelected: Bool {
        !items.isEmpty && Set(items.map(\.id)).isSubset(of: selectedIDs)
    }
}

private struct ArchivedItemsView: View {
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var allItems: [CaptureItem]
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()

    private var items: [CaptureItem] {
        allItems.filter { $0.parentCaptureID == nil && $0.isArchived }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("No archived captures", systemImage: "archivebox")
            } else {
                List(items, id: \.id) { item in
                    if isSelecting {
                        Button {
                            toggleSelection(for: item)
                        } label: {
                            HStack(spacing: 10) {
                                CaptureSelectionIndicator(isSelected: selectedIDs.contains(item.id))
                                CaptureRow(item: item)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            CaptureDetailView(item: item)
                        } label: {
                            CaptureRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Archive")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs.removeAll() }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button(areAllItemsSelected ? "Clear" : "All") {
                        if areAllItemsSelected {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(items.map(\.id))
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                CaptureBulkActionBar(
                    selectedIDs: $selectedIDs,
                    isSelecting: $isSelecting,
                    allItems: allItems,
                    mode: .archived
                )
            }
        }
    }

    private func toggleSelection(for item: CaptureItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private var areAllItemsSelected: Bool {
        !items.isEmpty && Set(items.map(\.id)).isSubset(of: selectedIDs)
    }
}

private struct CaptureSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? .indigo : .secondary)
            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }
}

private enum CaptureBulkMode {
    case active
    case archived

    var archiveTitle: String {
        switch self {
        case .active: "Archive"
        case .archived: "Restore from Archive"
        }
    }

    var archiveSymbol: String {
        switch self {
        case .active: "archivebox"
        case .archived: "arrow.uturn.backward"
        }
    }

    var archiveValue: Bool {
        self == .active
    }
}

private struct CaptureBulkActionBar: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedIDs: Set<UUID>
    @Binding var isSelecting: Bool
    let allItems: [CaptureItem]
    let mode: CaptureBulkMode

    @AppStorage("customSmartBlocksData") private var customBlocksData = Data()
    @State private var showsMoveSheet = false
    @State private var showsTagSheet = false
    @State private var showsSmartBlockSheet = false
    @State private var showsDeleteConfirmation = false

    private var selectedRoots: [CaptureItem] {
        allItems.filter { $0.parentCaptureID == nil && selectedIDs.contains($0.id) }
    }

    private var selectedCount: Int {
        selectedRoots.count
    }

    private var collectionNames: [String] {
        Array(Set(allItems.filter { $0.parentCaptureID == nil }.map(\.collectionName)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var customBlocks: [CustomSmartBlock] {
        guard !customBlocksData.isEmpty,
              let blocks = try? JSONDecoder().decode([CustomSmartBlock].self, from: customBlocksData) else {
            return []
        }
        return blocks.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(selectedCount == 1 ? "1 capture block selected" : "\(selectedCount) capture blocks selected")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    showsMoveSheet = true
                } label: {
                    Label("Move", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    showsTagSheet = true
                } label: {
                    Label("Tags", systemImage: "tag")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button {
                        showsSmartBlockSheet = true
                    } label: {
                        Label("Add to Smart Block", systemImage: "square.stack.3d.up")
                    }

                    Button {
                        setArchived(mode.archiveValue)
                    } label: {
                        Label(mode.archiveTitle, systemImage: mode.archiveSymbol)
                    }

                    Divider()

                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .disabled(selectedCount == 0)
        .sheet(isPresented: $showsMoveSheet) {
            BulkMoveCollectionSheet(collectionNames: collectionNames) { collectionName in
                moveSelectedBlocks(to: collectionName)
            }
        }
        .sheet(isPresented: $showsTagSheet) {
            BulkTagsSheet { addTags, removeTags in
                updateTags(addTags: addTags, removeTags: removeTags)
            }
        }
        .sheet(isPresented: $showsSmartBlockSheet) {
            BulkSmartBlockPicker(
                blocks: customBlocks,
                onSelect: addSelectedBlocks(to:),
                onCreate: createSmartBlock(title:keywords:)
            )
        }
        .confirmationDialog(
            "Delete \(selectedCount) capture \(selectedCount == 1 ? "block" : "blocks")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedBlocks()
            }
        } message: {
            Text("The selected captures, their linked notes and recordings, and local files will be permanently removed from this iPhone.")
        }
    }

    private func moveSelectedBlocks(to collectionName: String) {
        for item in itemsInSelectedBlocks {
            item.collectionName = collectionName
        }
    }

    private func updateTags(addTags: String, removeTags: String) {
        let additions = tags(from: addTags)
        let removals = Set(tags(from: removeTags).map { $0.lowercased() })

        for item in selectedRoots {
            var updatedTags = item.tags.filter { !removals.contains($0.lowercased()) }
            for tag in additions where !updatedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                updatedTags.append(tag)
            }
            item.tagsText = updatedTags.joined(separator: ", ")
        }
    }

    private func addSelectedBlocks(to block: CustomSmartBlock) {
        let updatedBlocks = customBlocks.map { currentBlock in
            currentBlock.id == block.id ? currentBlock.including(selectedIDs) : currentBlock
        }
        save(blocks: updatedBlocks)
    }

    private func createSmartBlock(title: String, keywords: String) {
        var blocks = customBlocks
        blocks.append(CustomSmartBlock(title: title, keywordsText: keywords, manualCaptureIDs: Array(selectedIDs)))
        save(blocks: blocks)
    }

    private func setArchived(_ isArchived: Bool) {
        for item in itemsInSelectedBlocks {
            item.isArchived = isArchived
        }
        finishSelection()
    }

    private func deleteSelectedBlocks() {
        for item in itemsInSelectedBlocks {
            if let fileName = item.assetFileName {
                LocalFileStore.remove(fileName: fileName)
            }
            modelContext.delete(item)
        }
        finishSelection()
    }

    private var itemsInSelectedBlocks: [CaptureItem] {
        var includedIDs = Set(selectedRoots.map(\.id))
        var foundNewItem = true

        while foundNewItem {
            foundNewItem = false
            for item in allItems where !includedIDs.contains(item.id) && item.parentCaptureID.map(includedIDs.contains) == true {
                includedIDs.insert(item.id)
                foundNewItem = true
            }
        }

        return allItems.filter { includedIDs.contains($0.id) }
    }

    private func tags(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func save(blocks: [CustomSmartBlock]) {
        customBlocksData = (try? JSONEncoder().encode(blocks)) ?? customBlocksData
    }

    private func finishSelection() {
        selectedIDs.removeAll()
        isSelecting = false
    }
}

private struct BulkMoveCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let collectionNames: [String]
    let onMove: (String) -> Void
    @State private var newCollectionName = ""

    var body: some View {
        NavigationStack {
            Form {
                if !collectionNames.isEmpty {
                    Section("Existing collections") {
                        ForEach(collectionNames, id: \.self) { collectionName in
                            Button(collectionName) {
                                onMove(collectionName)
                                dismiss()
                            }
                        }
                    }
                }

                Section("New collection") {
                    TextField("Collection name", text: $newCollectionName)
                    Button("Move here") {
                        onMove(cleanedNewCollectionName)
                        dismiss()
                    }
                    .disabled(cleanedNewCollectionName.isEmpty)
                }
            }
            .navigationTitle("Move capture blocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var cleanedNewCollectionName: String {
        newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BulkTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onApply: (String, String) -> Void
    @State private var addTags = ""
    @State private var removeTags = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Add tags") {
                    TextField("idea, person, follow-up", text: $addTags, axis: .vertical)
                    Text("Separate tags with commas or new lines.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Remove tags") {
                    TextField("receipt, old", text: $removeTags, axis: .vertical)
                    Text("Removal is case-insensitive.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(addTags, removeTags)
                        dismiss()
                    }
                    .disabled(addTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && removeTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct BulkSmartBlockPicker: View {
    @Environment(\.dismiss) private var dismiss
    let blocks: [CustomSmartBlock]
    let onSelect: (CustomSmartBlock) -> Void
    let onCreate: (String, String) -> Void
    @State private var isCreatingBlock = false
    @State private var title = ""
    @State private var keywords = ""

    var body: some View {
        NavigationStack {
            Group {
                if isCreatingBlock {
                    Form {
                        Section("Block") {
                            TextField("Name, for example People to follow up", text: $title)
                        }

                        Section("Automatic matching, optional") {
                            TextEditor(text: $keywords)
                                .frame(minHeight: 110)
                            Text("The selected capture blocks are added now. Keywords add future matching captures automatically.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("New Smart Block")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") { isCreatingBlock = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                onCreate(title.trimmingCharacters(in: .whitespacesAndNewlines), keywords)
                                dismiss()
                            }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } else {
                    List {
                        if blocks.isEmpty {
                            ContentUnavailableView {
                                Label("No Smart Blocks yet", systemImage: "square.stack.3d.up")
                            } description: {
                                Text("Create one now, or create blocks later from the Smart tab.")
                            }
                        } else {
                            Section("Choose a Smart Block") {
                                ForEach(blocks) { block in
                                    Button {
                                        onSelect(block)
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(block.title)
                                            if !block.keywordsText.isEmpty {
                                                Text(block.keywordsText)
                                                    .font(.footnote)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Section {
                            Button {
                                isCreatingBlock = true
                            } label: {
                                Label("Create Smart Block", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                    .navigationTitle("Add to Smart Block")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
            }
        }
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
                    NavigationLink {
                        MacSyncView()
                    } label: {
                        Label("Sync to Mac", systemImage: "laptopcomputer.and.iphone")
                    }
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

private struct MacSyncView: View {
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var captures: [CaptureItem]
    @AppStorage("macSyncEndpoint") private var endpoint = ""
    @AppStorage("macSyncPairingToken") private var pairingToken = ""
    @AppStorage("macSyncLastSuccess") private var lastSuccess = 0.0
    @StateObject private var nearbySync = NearbyMacSyncService()
    @State private var isSyncing = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                SecureField("Pairing token from your Mac", text: $pairingToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Pair your Mac once")
            } footer: {
                Text("Start Memory Space Nearby Bridge on your Mac and enter its pairing token here. After that, nearby syncing needs only one tap.")
            }

            Section {
                if nearbySync.nearbyMacs.isEmpty {
                    Text(nearbySync.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Find nearby Macs") {
                        nearbySync.startBrowsing()
                    }
                } else {
                    ForEach(nearbySync.nearbyMacs) { mac in
                        Button {
                            Task { await syncNearby(to: mac) }
                        } label: {
                            HStack {
                                Label(mac.name, systemImage: "laptopcomputer")
                                Spacer()
                                if isSyncing {
                                    ProgressView()
                                } else {
                                    Text("Sync")
                                        .foregroundStyle(.indigo)
                                }
                            }
                        }
                        .disabled(isSyncing || pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } header: {
                Text("Sync to a nearby Mac")
            } footer: {
                Text("No router or internet is needed. Keep Wi‑Fi and Bluetooth turned on, and keep both devices nearby while syncing.")
            }

            Section {
                TextField("http://192.168.1.20:8787", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Button("Test connection") {
                    Task { await testConnection() }
                }
                .disabled(isSyncing || endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Wi‑Fi fallback")
            } footer: {
                Text("Use this only if nearby discovery is unavailable. Start Memory Space Bridge on your Mac; it prints the address and uses the same pairing token.")
            }

            Section("Manual sync") {
                Button {
                    Task { await syncNow() }
                } label: {
                    HStack {
                        Label(isSyncing ? "Syncing…" : "Sync to Mac now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncing || endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if lastSuccess > 0 {
                    LabeledContent("Last sync") {
                        Text(Date(timeIntervalSince1970: lastSuccess), format: .dateTime.day().month().hour().minute())
                    }
                }
            }

            Section("What your Mac receives") {
                Label("Titles, notes, transcripts, tags, and Smart Blocks", systemImage: "text.alignleft")
                Label("Compressed copies of screenshots and images", systemImage: "photo")
                Label("Voice recordings stay on the iPhone; their transcript syncs", systemImage: "waveform")
            }

            Section("Privacy") {
                Text("Nearby sync uses a pairing token and works without internet or a Wi‑Fi router. The IP-address fallback is only for trusted private Wi‑Fi because it does not use TLS yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(message.hasPrefix("Synced") || message.hasPrefix("Connection") ? .green : .red)
                }
            }
        }
        .navigationTitle("Sync to Mac")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nearbySync.startBrowsing()
        }
        .onDisappear {
            nearbySync.stopBrowsing()
        }
    }

    @MainActor
    private func testConnection() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await MacSyncService.testConnection(endpointText: endpoint)
            message = "Connection to your Mac is working."
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await MacSyncService.sync(captures: captures, endpointText: endpoint, pairingToken: pairingToken)
            lastSuccess = result.updatedAt.timeIntervalSince1970
            message = "Synced \(result.receivedCaptures) captures to your Mac."
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func syncNearby(to mac: NearbyMac) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let data = try MacSyncService.nearbySyncData(captures: captures, pairingToken: pairingToken)
            try await nearbySync.sync(data: data, to: mac)
            lastSuccess = Date.now.timeIntervalSince1970
            message = "Synced \(captures.count) captures directly to \(mac.name)."
        } catch {
            message = error.localizedDescription
        }
    }
}
