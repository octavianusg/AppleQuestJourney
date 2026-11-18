import Foundation
import SwiftData
import Testing
@testable import AppleQuestJourney

@Suite("SavedQuest SwiftData Persistence & Offline Resilience Tests")
@MainActor
struct SavedQuestPersistenceTests {
    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SavedQuest.self, configurations: config)
    }

    @Test("Completing a quest persists all fields and LearningResource URLs in SwiftData (REQ-S08, REQ-S09)")
    func completingQuestPersistsSnapshotAndResources() throws {
        let container = try makeInMemoryContainer()
        let store = SavedQuestStore(modelContext: container.mainContext)
        let completionDate = Date(timeIntervalSince1970: 1_750_000_000)

        let originalQuest = Quest(
            id: "quest-swiftdata-1",
            title: "Spot the Everyday Mug",
            questDescription: "Experience VNClassifyImageRequest on a coffee mug.",
            status: .published,
            publishDate: completionDate.addingTimeInterval(-3600),
            targetLabel: "coffee_cup",
            hintText: "Check the breakroom counter!",
            resources: [
                LearningResource(
                    title: "Apple Developer: VNClassifyImageRequest",
                    urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
                ),
                LearningResource(
                    title: "WWDC: Explore Computer Vision APIs",
                    urlString: "https://developer.apple.com/videos/vision"
                )
            ]
        )

        let saved = try store.saveCompletedQuest(
            originalQuest,
            detectedConfidence: 0.93,
            completedAt: completionDate
        )

        #expect(saved.questID == "quest-swiftdata-1")
        #expect(saved.title == "Spot the Everyday Mug")
        #expect(saved.questDescription == "Experience VNClassifyImageRequest on a coffee mug.")
        #expect(saved.targetLabel == "coffee_cup")
        #expect(saved.detectedConfidence == 0.93)
        #expect(saved.confidencePercentageText == "93%")
        #expect(saved.hintText == "Check the breakroom counter!")
        #expect(saved.completedAt == completionDate)
        #expect(saved.resources.count == 2)
        #expect(saved.resources[0].validURL?.absoluteString == "https://developer.apple.com/documentation/vision/vnclassifyimagerequest")
        #expect(saved.resources[1].validURL?.absoluteString == "https://developer.apple.com/videos/vision")

        let fetchedAll = try store.fetchAllSavedQuests()
        #expect(fetchedAll.count == 1)
        #expect(fetchedAll.first?.questID == "quest-swiftdata-1")
    }

    @Test("Mentor editing or deleting a Quest in CloudKit leaves the student's SavedQuest in SwiftData completely untouched (REQ-S10)")
    func mentorCloudKitEditsOrDeletionsDoNotAffectLocalSavedQuest() async throws {
        let container = try makeInMemoryContainer()
        let store = SavedQuestStore(modelContext: container.mainContext)

        let originalQuest = Quest(
            id: "quest-resilient",
            title: "Original Mentor Title",
            questDescription: "Original mentor description before edits.",
            status: .published,
            publishDate: .now.addingTimeInterval(-1800),
            targetLabel: "keyboard",
            hintText: "Original hint",
            resources: [
                LearningResource(
                    title: "Original Vision Guide",
                    urlString: "https://developer.apple.com/documentation/vision"
                )
            ]
        )

        let repository = InMemoryQuestRepository(initialQuests: [originalQuest])

        // 1. Student completes and saves Quest A locally in SwiftData
        _ = try store.saveCompletedQuest(originalQuest, detectedConfidence: 0.88)

        // 2. Mentor edits Quest A in CloudKit (changing title, targetLabel, and removing resources)
        var editedByMentor = originalQuest
        editedByMentor.title = "Mutated Title"
        editedByMentor.targetLabel = "laptop"
        editedByMentor.resources = []
        _ = try await repository.saveQuest(editedByMentor)

        // 3. Mentor then deletes Quest A from CloudKit completely
        try await repository.deleteQuest(id: originalQuest.id)
        let remainingInCloud = try await repository.fetchAllQuestsForMentor()
        #expect(remainingInCloud.isEmpty)

        // 4. Student's Saved Library in SwiftData retains the exact original snapshot and unlocked URLs (REQ-S10)
        let savedInLibrary = try store.fetchSavedQuest(questID: "quest-resilient")
        #expect(savedInLibrary != nil)
        #expect(savedInLibrary?.title == "Original Mentor Title")
        #expect(savedInLibrary?.questDescription == "Original mentor description before edits.")
        #expect(savedInLibrary?.targetLabel == "keyboard")
        #expect(savedInLibrary?.resources.count == 1)
        #expect(savedInLibrary?.resources.first?.title == "Original Vision Guide")
        #expect(savedInLibrary?.resources.first?.urlString == "https://developer.apple.com/documentation/vision")
    }

    @Test("Fetching from SwiftData succeeds when QuestRepository simulates an offline network error (REQ-S11, REQ-S12)")
    func offlineSavedLibraryAccessAndReplaySnapshot() async throws {
        let container = try makeInMemoryContainer()
        let store = SavedQuestStore(modelContext: container.mainContext)

        let completedQuest = Quest(
            id: "quest-offline",
            title: "Offline Vision Quest",
            questDescription: "Available forever even without internet.",
            status: .published,
            publishDate: .now.addingTimeInterval(-7200),
            targetLabel: "coffee_cup",
            hintText: "Look near the mug rack",
            resources: [
                LearningResource(
                    title: "Apple Vision Framework",
                    urlString: "https://developer.apple.com/documentation/vision"
                )
            ]
        )

        _ = try store.saveCompletedQuest(completedQuest, detectedConfidence: 0.81)

        // Simulate complete offline failure on the CloudKit repository
        let offlineRepo = InMemoryQuestRepository(
            initialQuests: [],
            simulatedError: .cloudKitUnavailable("The Internet connection appears to be offline.")
        )

        await #expect(throws: QuestRepositoryError.self) {
            _ = try await offlineRepo.fetchPublishedQuestsForStudent(at: .now)
        }

        // Saved Library loads from local SwiftData without any network dependency (REQ-S11)
        let offlineSavedQuests = try store.fetchAllSavedQuests()
        #expect(offlineSavedQuests.count == 1)

        let savedItem = try #require(offlineSavedQuests.first)
        #expect(savedItem.title == "Offline Vision Quest")
        #expect(savedItem.resources.count == 1)

        // Replaying the quest with a higher confidence score updates the best confidence while preserving snapshot metadata (REQ-S12)
        let replaySnapshot = savedItem.asQuestSnapshot
        #expect(replaySnapshot.targetLabel == "coffee_cup")
        #expect(replaySnapshot.hintText == "Look near the mug rack")

        _ = try store.saveCompletedQuest(replaySnapshot, detectedConfidence: 0.96)
        let updatedSaved = try store.fetchSavedQuest(questID: "quest-offline")
        #expect(updatedSaved?.detectedConfidence == 0.96)
    }
}
