import Foundation
import Testing
@testable import AppleQuestJourney

@MainActor
struct MentorViewModelTests {

    @Test("MentorViewModel creates a draft quest and filters Drafts (REQ-M01)")
    func createAndSaveDraftQuest() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
        let repository = InMemoryQuestRepository()
        let viewModel = MentorViewModel(repository: repository, nowProvider: { fixedNow })

        let validLabel = try #require(VisionClassifierService.supportedTaxonomyLabels().first)
        let draftInput = Quest(
            id: "quest-mentor-draft-1",
            title: "Discover Scene Classification",
            questDescription: "Point your camera at an object and inspect VNClassifyImageRequest.",
            status: .published, // saveAsDraft should force .draft
            publishDate: fixedNow,
            targetLabel: validLabel,
            hintText: "Look on your desk!",
            resources: [
                LearningResource(
                    title: "Vision Docs",
                    urlString: "https://developer.apple.com/documentation/vision"
                )
            ],
            updatedAt: fixedNow
        )

        let savedDraft = try await viewModel.saveAsDraft(draftInput)
        #expect(savedDraft.status == .draft)
        #expect(savedDraft.displayState(at: fixedNow) == .draft)
        #expect(viewModel.quests.count == 1)
        #expect(viewModel.count(for: .drafts) == 1)
        #expect(viewModel.count(for: .scheduled) == 0)
        #expect(viewModel.count(for: .publishedLive) == 0)

        viewModel.selectedFilter = .drafts
        #expect(viewModel.filteredQuests.map(\.id) == ["quest-mentor-draft-1"])
    }

    @Test("MentorViewModel schedules a future quest and publishes a live quest (REQ-M02)")
    func scheduleAndPublishQuests() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
        let futureDate = fixedNow.addingTimeInterval(7200)
        let pastDate = fixedNow.addingTimeInterval(-3600)

        let repository = InMemoryQuestRepository()
        let viewModel = MentorViewModel(repository: repository, nowProvider: { fixedNow })
        let validLabel = try #require(VisionClassifierService.supportedTaxonomyLabels().first)
        let resource = LearningResource(
            title: "VNClassifyImageRequest",
            urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
        )

        // Schedule for future (REQ-M02)
        let scheduledQuest = Quest(
            id: "quest-scheduled-1",
            title: "Future Scheduled Quest",
            questDescription: "Goes live in 2 hours",
            status: .draft,
            publishDate: fixedNow,
            targetLabel: validLabel,
            resources: [resource],
            updatedAt: fixedNow
        )
        let savedScheduled = try await viewModel.publishQuest(scheduledQuest, publishDate: futureDate)
        #expect(savedScheduled.status == .published)
        #expect(savedScheduled.publishDate == futureDate)
        #expect(savedScheduled.displayState(at: fixedNow) == .scheduled)

        // Publish live immediately (REQ-M02)
        let liveQuest = Quest(
            id: "quest-live-1",
            title: "Immediate Live Quest",
            questDescription: "Already live for students",
            status: .draft,
            publishDate: pastDate,
            targetLabel: validLabel,
            resources: [resource],
            updatedAt: fixedNow
        )
        let savedLive = try await viewModel.publishQuest(liveQuest, publishDate: pastDate)
        #expect(savedLive.status == .published)
        #expect(savedLive.displayState(at: fixedNow) == .publishedLive)

        #expect(viewModel.count(for: .all) == 2)
        #expect(viewModel.count(for: .scheduled) == 1)
        #expect(viewModel.count(for: .publishedLive) == 1)

        viewModel.selectedFilter = .scheduled
        #expect(viewModel.filteredQuests.map(\.id) == ["quest-scheduled-1"])

        viewModel.selectedFilter = .publishedLive
        #expect(viewModel.filteredQuests.map(\.id) == ["quest-live-1"])
    }

    @Test("MentorViewModel edits an existing quest and deletes a quest (REQ-M03, REQ-M04)")
    func editAndDeleteQuest() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
        let labels = VisionClassifierService.supportedTaxonomyLabels()
        let firstLabel = try #require(labels.first)
        let secondLabel = labels.dropFirst().first ?? firstLabel

        let initialQuest = Quest(
            id: "quest-edit-delete-1",
            title: "Original Quest Title",
            questDescription: "Original description",
            status: .draft,
            publishDate: fixedNow,
            targetLabel: firstLabel,
            hintText: "Original hint",
            resources: [
                LearningResource(
                    title: "Initial Resource",
                    urlString: "https://developer.apple.com/documentation/vision"
                )
            ],
            updatedAt: fixedNow
        )

        let repository = InMemoryQuestRepository(initialQuests: [initialQuest])
        let viewModel = MentorViewModel(repository: repository, nowProvider: { fixedNow })

        await viewModel.loadQuests()
        #expect(viewModel.quests.count == 1)
        #expect(viewModel.selectedQuest?.title == "Original Quest Title")

        // Edit fields and publish (REQ-M03)
        var edited = try #require(viewModel.selectedQuest)
        edited.title = "Edited Quest Title"
        edited.questDescription = "Updated description"
        edited.targetLabel = secondLabel
        edited.hintText = "   " // Should normalize to nil (REQ-M08)

        let updated = try await viewModel.publishQuest(edited, publishDate: fixedNow)
        #expect(updated.title == "Edited Quest Title")
        #expect(updated.targetLabel == secondLabel)
        #expect(updated.hintText == nil)
        #expect(updated.status == .published)

        // Verify persisted in repository
        let repoQuests = try await repository.fetchAllQuestsForMentor()
        #expect(repoQuests.count == 1)
        #expect(repoQuests.first?.title == "Edited Quest Title")

        // Delete quest (REQ-M04)
        try await viewModel.deleteQuest(id: "quest-edit-delete-1")
        #expect(viewModel.quests.isEmpty)
        #expect(viewModel.selectedQuest == nil)

        let remainingInRepo = try await repository.fetchAllQuestsForMentor()
        #expect(remainingInRepo.isEmpty)
    }
}
