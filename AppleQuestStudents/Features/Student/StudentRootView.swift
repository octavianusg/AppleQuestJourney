import SwiftData
import SwiftUI

/// Tabs available in the zero-login iOS Student Developer App (`REQ-S01`).
nonisolated enum StudentAppTab: String, CaseIterable, Identifiable, Sendable {
    case activeQuests = "Active Quests"
    case savedLibrary = "Saved Library"

    var id: String { rawValue }
}

/// Zero-login root `TabView` for the iOS Student Developer App (`REQ-S01`, `REQ-S09`, `REQ-S11`, `REQ-S12`).
struct StudentRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedQuest.completedAt, order: .reverse)
    private var savedQuests: [SavedQuest]

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
                ActiveQuestsView(
                    viewModel: activeQuestsViewModel,
                    onQuestCompleted: { quest, confidence in
                        persistCompletedQuest(quest, confidence: confidence)
                    }
                )
            }

            Tab("Saved Library", systemImage: "books.vertical.fill", value: .savedLibrary) {
                SavedLibraryView(
                    onBrowseActiveQuests: {
                        selectedTab = .activeQuests
                    },
                    onReplayCompleted: { savedQuest, newConfidence in
                        persistCompletedQuest(savedQuest.asQuestSnapshot, confidence: newConfidence)
                    }
                )
            }
        }
        .onAppear {
            syncSavedQuestsIntoActiveFeed()
        }
        .onChange(of: savedQuests.count) { _, _ in
            syncSavedQuestsIntoActiveFeed()
        }
    }

    private func syncSavedQuestsIntoActiveFeed() {
        var ids = Set<String>()
        var confidences: [String: Double] = [:]
        for item in savedQuests {
            ids.insert(item.questID)
            confidences[item.questID] = item.detectedConfidence
        }
        activeQuestsViewModel.syncCompletedQuestIDs(ids, confidences: confidences)
    }

    private func persistCompletedQuest(_ quest: Quest, confidence: Double) {
        activeQuestsViewModel.markQuestCompleted(quest, confidence: confidence)
        let store = SavedQuestStore(modelContext: modelContext)
        _ = try? store.saveCompletedQuest(quest, detectedConfidence: confidence)
    }
}

#Preview("Student Root TabView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: SavedQuest.self, configurations: config)
    let sampleQuests = InMemoryQuestRepository.previewSampleQuests
    let repo = InMemoryQuestRepository(initialQuests: sampleQuests)
    let vm = ActiveQuestsViewModel(repository: repo)
    vm.activeQuests = sampleQuests.filter { QuestCKRecordMapper.isVisibleToStudent($0, at: .now) }
    return StudentRootView(activeQuestsViewModel: vm)
        .modelContainer(container)
}
