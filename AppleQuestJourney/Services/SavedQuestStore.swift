import Foundation
import SwiftData

/// Manages local SwiftData persistence of completed quests (`SavedQuest`) on the student's iOS device (`REQ-S09`, `REQ-S10`, `REQ-S11`, `REQ-S12`).
/// Explicitly decoupled from CloudKit updates or deletions so that once a student completes and saves a quest, mentor edits or deletions in CloudKit never remove or overwrite the student's saved local copy (`REQ-S10`).
@MainActor
final class SavedQuestStore {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Saves an immutable `SavedQuest` snapshot when a student completes the Vision Scavenger Hunt (`REQ-S09`).
    /// If the quest was already saved locally, preserves the original snapshot metadata and resources (`REQ-S10`) while updating `detectedConfidence` if the student achieved a higher score on replay (`REQ-S12`).
    @discardableResult
    func saveCompletedQuest(
        _ quest: Quest,
        detectedConfidence: Double,
        completedAt: Date = .now
    ) throws -> SavedQuest {
        let clampedConfidence = min(max(detectedConfidence, 0.0), 1.0)

        if let existing = try fetchSavedQuest(questID: quest.id) {
            if clampedConfidence > existing.detectedConfidence {
                existing.detectedConfidence = clampedConfidence
            }
            try modelContext.save()
            return existing
        }

        let snapshot = SavedQuest(
            from: quest,
            detectedConfidence: clampedConfidence,
            completedAt: completedAt
        )
        modelContext.insert(snapshot)
        try modelContext.save()
        return snapshot
    }

    /// Fetches all locally saved completed quests sorted by most recently completed (`REQ-S09`, `REQ-S11`).
    /// Reads exclusively from local `SwiftData` and never requires network access (`REQ-S11`).
    func fetchAllSavedQuests() throws -> [SavedQuest] {
        let descriptor = FetchDescriptor<SavedQuest>(
            sortBy: [SortDescriptor(\SavedQuest.completedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches a specific `SavedQuest` by its `questID` if completed locally.
    func fetchSavedQuest(questID: String) throws -> SavedQuest? {
        let targetID = questID
        var descriptor = FetchDescriptor<SavedQuest>(
            predicate: #Predicate<SavedQuest> { $0.questID == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Returns the set of completed `questID`s and their highest achieved confidence scores from local SwiftData (`REQ-S09`, `REQ-S12`).
    func completedStatemap() throws -> (ids: Set<String>, confidences: [String: Double]) {
        let saved = try fetchAllSavedQuests()
        var ids = Set<String>()
        var confidences: [String: Double] = [:]
        for item in saved {
            ids.insert(item.questID)
            confidences[item.questID] = item.detectedConfidence
        }
        return (ids, confidences)
    }
}
