import SwiftUI

#if os(macOS)
/// Primary 2-column macOS Mentor Dashboard (`NavigationSplitView`) for browsing, filtering, creating, editing, scheduling, and deleting Quests (`REQ-M01`–`REQ-M08`).
struct MentorDashboardView: View {
    @State private var viewModel: MentorViewModel
    @State private var activeDraftQuest: Quest?
    @State private var questPendingDeletion: Quest?

    init(viewModel: MentorViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? MentorViewModel())
    }

    var body: some View {
        NavigationSplitView {
            sidebarQuestColumnView
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            detailPaneView
        }
        .navigationTitle("Apple Quest Journey — Mentor Studio")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    startCreatingNewQuest()
                } label: {
                    Label("New Quest", systemImage: "plus")
                }
                .help("Create a new Vision Scavenger Hunt quest")

                Button {
                    Task {
                        await viewModel.loadQuests()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload quests from CloudKit Public Database")
                .disabled(viewModel.isLoading)
            }
        }
        .confirmationDialog(
            "Delete Quest?",
            isPresented: Binding(
                get: { questPendingDeletion != nil },
                set: { if !$0 { questPendingDeletion = nil } }
            ),
            presenting: questPendingDeletion
        ) { quest in
            Button("Delete \"\(quest.title)\"", role: .destructive) {
                Task {
                    try? await viewModel.deleteQuest(quest)
                    if activeDraftQuest?.id == quest.id {
                        activeDraftQuest = viewModel.selectedQuest
                    }
                    questPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                questPendingDeletion = nil
            }
        } message: { quest in
            Text("This will permanently remove \"\(quest.title)\" from the CloudKit Public Database.")
        }
        .task {
            if viewModel.quests.isEmpty {
                await viewModel.loadQuests()
                activeDraftQuest = viewModel.selectedQuest
            }
        }
        .onChange(of: viewModel.selectedQuestID) { _, newID in
            if let selected = viewModel.quests.first(where: { $0.id == newID }) {
                activeDraftQuest = selected
            }
        }
    }

    // MARK: - Sidebar + Quest List Column

    private var sidebarQuestColumnView: some View {
        VStack(spacing: 0) {
            filterHeaderView
            Divider()
            questListView
        }
    }

    private var filterHeaderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title or Vision label…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MentorQuestFilter.allCases) { filter in
                        let isSelected = viewModel.selectedFilter == filter
                        Button {
                            viewModel.selectedFilter = filter
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: filter.systemImage)
                                    .font(.caption)
                                Text(filter.rawValue)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                Text("\(viewModel.count(for: filter))")
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.primary.opacity(0.12), in: Capsule())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }

    private var questListView: some View {
        Group {
            if viewModel.isLoading && viewModel.quests.isEmpty {
                ProgressView("Loading Quests from CloudKit…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredQuests.isEmpty {
                ContentUnavailableView {
                    Label("No Quests Found", systemImage: "sparkles.rectangle.stack")
                } description: {
                    Text(emptyStateDescription)
                } actions: {
                    Button {
                        startCreatingNewQuest()
                    } label: {
                        Label("Create Quest", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredQuests) { quest in
                            let isSelected = viewModel.selectedQuestID == quest.id
                            Button {
                                viewModel.selectedQuestID = quest.id
                                activeDraftQuest = quest
                            } label: {
                                MentorQuestRowView(quest: quest, isSelected: isSelected)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    questPendingDeletion = quest
                                } label: {
                                    Label("Delete Quest…", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPaneView: some View {
        VStack(spacing: 0) {
            if let banner = viewModel.statusBannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(banner)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        viewModel.statusBannerMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.green.opacity(0.12))
                Divider()
            }

            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.red.opacity(0.12))
                Divider()
            }

            if let quest = activeDraftQuest ?? viewModel.selectedQuest {
                QuestEditorView(
                    quest: quest,
                    isExistingQuest: viewModel.quests.contains(where: { $0.id == quest.id }),
                    isSaving: viewModel.isSaving,
                    onSaveAsDraft: { updatedQuest in
                        Task {
                            if let saved = try? await viewModel.saveAsDraft(updatedQuest) {
                                activeDraftQuest = saved
                            }
                        }
                    },
                    onPublish: { updatedQuest, publishDate in
                        Task {
                            if let saved = try? await viewModel.publishQuest(updatedQuest, publishDate: publishDate) {
                                activeDraftQuest = saved
                            }
                        }
                    },
                    onDelete: {
                        questPendingDeletion = quest
                    }
                )
                .id(quest.id)
            } else {
                ContentUnavailableView {
                    Label("Select or Create a Quest", systemImage: "viewfinder.circle")
                } description: {
                    Text("Configure a Vision Scavenger Hunt quest, pick a valid taxonomy label, attach learning resources, and schedule when it goes live for students.")
                } actions: {
                    Button {
                        startCreatingNewQuest()
                    } label: {
                        Label("New Quest", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var emptyStateDescription: String {
        switch viewModel.selectedFilter {
        case .all:
            return "Create your first Vision Scavenger Hunt quest to share with Student Developers."
        case .drafts:
            return "No draft quests right now."
        case .scheduled:
            return "No quests are currently scheduled for a future publish date."
        case .publishedLive:
            return "No quests are currently live for students."
        }
    }

    private func startCreatingNewQuest() {
        let newQuest = viewModel.makeNewQuestTemplate()
        viewModel.selectedQuestID = nil
        activeDraftQuest = newQuest
    }
}

/// Row item in the Mentor Dashboard's quest list showing title, target Vision taxonomy badge, status badge, and publish date.
struct MentorQuestRowView: View {
    let quest: Quest
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(quest.title.isEmpty ? "Untitled Quest" : quest.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                MentorStatusBadge(state: quest.displayState())
            }

            if !quest.questDescription.isEmpty {
                Text(quest.questDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label(quest.targetLabel, systemImage: "viewfinder")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.blue)

                Label("\(quest.resources.count) URL\(quest.resources.count == 1 ? "" : "s")", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if quest.status == .published {
                    Text(quest.publishDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }
}

/// Color-coded pill badge indicating Draft, Scheduled, or Published Live status.
struct MentorStatusBadge: View {
    let state: MentorQuestDisplayState

    var body: some View {
        Text(state.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.16), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch state {
        case .draft:
            return .secondary
        case .scheduled:
            return .orange
        case .publishedLive:
            return .green
        }
    }
}

#Preview("Mentor Dashboard") {
    let sampleQuests = InMemoryQuestRepository.previewSampleQuests
    let repo = InMemoryQuestRepository(initialQuests: sampleQuests)
    let vm = MentorViewModel(repository: repo)
    vm.quests = sampleQuests
    vm.selectedQuestID = sampleQuests.first?.id
    return MentorDashboardView(viewModel: vm)
        .frame(width: 1040, height: 720)
}
#endif
