import Foundation
import SwiftData

@MainActor
final class SavedQuestStore {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

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

    func fetchAllSavedQuests() throws -> [SavedQuest] {
        let descriptor = FetchDescriptor<SavedQuest>(
            sortBy: [SortDescriptor(\SavedQuest.completedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }


    func fetchSavedQuest(questID: String) throws -> SavedQuest? {
        let targetID = questID
        var descriptor = FetchDescriptor<SavedQuest>(
            predicate: #Predicate<SavedQuest> { $0.questID == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

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
