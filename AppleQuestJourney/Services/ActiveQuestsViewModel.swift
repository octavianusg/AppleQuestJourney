import Foundation
import Observation

/// Manages the Student App's Active Quests feed, completion state tracking, and resource lock/unlock visibility (`REQ-S02`, `REQ-S03`, `REQ-S08`, `REQ-S12`).
@Observable
@MainActor
final class ActiveQuestsViewModel {
    private let repository: any QuestRepositoryProtocol
    private let nowProvider: @Sendable () -> Date

    /// Published quests visible to students (`status == .published && publishDate <= now`).
    var activeQuests: [Quest] = []

    /// Set of Quest IDs that the student has completed (synced from local SwiftData `SavedQuest` records or in-session completions).
    var completedQuestIDs: Set<String> = []

    /// Optional map of highest achieved confidence per completed Quest ID (`0.0`–`1.0`).
    var achievedConfidenceByQuestID: [String: Double] = [:]

    var isLoading: Bool = false
    var errorMessage: String?

    init(
        repository: any QuestRepositoryProtocol = CloudKitQuestRepository(),
        completedQuestIDs: Set<String> = [],
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.completedQuestIDs = completedQuestIDs
        self.nowProvider = nowProvider
    }

    /// Fetches only published quests whose `publishDate <= now` from the repository (`REQ-S02`).
    func loadActiveQuests() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let now = nowProvider()
        do {
            let fetched = try await repository.fetchPublishedQuestsForStudent(at: now)
            // Defensive double-check filter enforcing REQ-S02
            activeQuests = fetched
                .filter { QuestCKRecordMapper.isVisibleToStudent($0, at: now) }
                .sorted { $0.publishDate > $1.publishDate }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Synchronizes the set of completed quest IDs from local persistence (`REQ-S09`, `REQ-S12`).
    func syncCompletedQuestIDs(_ ids: Set<String>, confidences: [String: Double] = [:]) {
        completedQuestIDs.formUnion(ids)
        for (questID, confidence) in confidences {
            achievedConfidenceByQuestID[questID] = confidence
        }
    }

    /// Returns `true` if the student has completed the given quest (`REQ-S03`, `REQ-S12`).
    func isCompleted(_ quest: Quest) -> Bool {
        completedQuestIDs.contains(quest.id)
    }

    /// Returns `true` if the student has completed the quest with `questID` (`REQ-S03`, `REQ-S12`).
    func isCompleted(questID: String) -> Bool {
        completedQuestIDs.contains(questID)
    }

    /// Returns the unlocked `LearningResource` items for a quest ONLY if the quest has been completed; otherwise returns `[]` (`REQ-S03`, `REQ-S08`, `REQ-S12`).
    func visibleResources(for quest: Quest) -> [LearningResource] {
        guard isCompleted(quest) else {
            return []
        }
        return quest.resources
    }

    /// Returns the primary call-to-action button title for a quest (`REQ-S04`, `REQ-S12`).
    func experienceActionTitle(for quest: Quest) -> String {
        isCompleted(quest) ? "Replay Vision Experience" : "Start Vision Experience"
    }

    /// Marks a quest as completed in the current session with the achieved Vision confidence score (`REQ-S07`, `REQ-S08`, `REQ-S12`).
    func markQuestCompleted(_ quest: Quest, confidence: Double) {
        completedQuestIDs.insert(quest.id)
        achievedConfidenceByQuestID[quest.id] = min(max(confidence, 0.0), 1.0)
    }
}
