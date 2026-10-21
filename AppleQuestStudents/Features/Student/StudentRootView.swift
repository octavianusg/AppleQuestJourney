import SwiftUI

/// Tabs available in the zero-login iOS Student Developer App (`REQ-S01`).
nonisolated enum StudentAppTab: String, CaseIterable, Identifiable, Sendable {
    case activeQuests = "Active Quests"
    case savedLibrary = "Saved Library"

    var id: String { rawValue }
}

/// Zero-login root `TabView` for the iOS Student Developer App (`REQ-S01`).
struct StudentRootView: View {
    @State private var selectedTab: StudentAppTab = .activeQuests
    @State private var activeQuestsViewModel: ActiveQuestsViewModel

    init(activeQuestsViewModel: ActiveQuestsViewModel? = nil) {
        _activeQuestsViewModel = State(
            initialValue: activeQuestsViewModel ?? ActiveQuestsViewModel()
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Active Quests", systemImage: "viewfinder.circle.fill", value: .activeQuests) {
                ActiveQuestsView(viewModel: activeQuestsViewModel)
            }

            Tab("Saved Library", systemImage: "books.vertical.fill", value: .savedLibrary) {
                savedLibraryPlaceholderView
            }
        }
    }

    /// Placeholder for the Saved Library tab (replaced by full SwiftData `SavedLibraryView` in Task 5.1).
    private var savedLibraryPlaceholderView: some View {
        NavigationStack {
            Group {
                if activeQuestsViewModel.completedQuestIDs.isEmpty {
                    ContentUnavailableView {
                        Label("Your Saved Library is Empty", systemImage: "books.vertical")
                    } description: {
                        Text("Complete a Vision Scavenger Hunt in Active Quests to unlock and permanently save mentor learning resources here.")
                    } actions: {
                        Button {
                            selectedTab = .activeQuests
                        } label: {
                            Label("Browse Active Quests", systemImage: "viewfinder.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(
                            activeQuestsViewModel.activeQuests.filter {
                                activeQuestsViewModel.isCompleted($0)
                            }
                        ) { completedQuest in
                            NavigationLink {
                                QuestDetailView(
                                    quest: completedQuest,
                                    isCompleted: true,
                                    achievedConfidence: activeQuestsViewModel.achievedConfidenceByQuestID[completedQuest.id]
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(completedQuest.title)
                                        .font(.headline)
                                    Text("\(completedQuest.resources.count) unlocked learning resource\(completedQuest.resources.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Library")
        }
    }
}

#Preview("Student Root TabView") {
    let sampleQuests = InMemoryQuestRepository.previewSampleQuests
    let repo = InMemoryQuestRepository(initialQuests: sampleQuests)
    let vm = ActiveQuestsViewModel(repository: repo)
    vm.activeQuests = sampleQuests.filter { QuestCKRecordMapper.isVisibleToStudent($0, at: .now) }
    return StudentRootView(activeQuestsViewModel: vm)
}
