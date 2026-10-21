import Foundation
import Testing
@testable import AppleQuestJourney

@MainActor
struct ActiveQuestsViewModelTests {

    @Test("ActiveQuestsViewModel only loads published quests where publishDate <= now, excluding drafts and future-scheduled quests (REQ-S02)")
    func loadsOnlyPublishedVisibleQuests() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_760_000_000)
        let resource = LearningResource(
            title: "VNClassifyImageRequest Documentation",
            urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
        )

        let draftQuest = Quest(
            id: "quest-draft",
            title: "Draft Quest",
            questDescription: "Hidden because draft",
            status: .draft,
            publishDate: fixedNow.addingTimeInterval(-3600),
            targetLabel: "coffee_cup",
            resources: [resource],
            updatedAt: fixedNow
        )

        let scheduledQuest = Quest(
            id: "quest-scheduled",
            title: "Future Scheduled Quest",
            questDescription: "Hidden because publishDate > now",
            status: .published,
            publishDate: fixedNow.addingTimeInterval(3600),
            targetLabel: "laptop",
            resources: [resource],
            updatedAt: fixedNow
        )

        let activePublishedQuest = Quest(
            id: "quest-active-live",
            title: "Live Published Quest",
            questDescription: "Visible to students",
            status: .published,
            publishDate: fixedNow.addingTimeInterval(-60),
            targetLabel: "keyboard",
            resources: [resource],
            updatedAt: fixedNow
        )

        let repository = InMemoryQuestRepository(
            initialQuests: [draftQuest, scheduledQuest, activePublishedQuest]
        )
        let viewModel = ActiveQuestsViewModel(
            repository: repository,
            nowProvider: { fixedNow }
        )

        await viewModel.loadActiveQuests()

        #expect(viewModel.activeQuests.count == 1)
        #expect(viewModel.activeQuests.first?.id == "quest-active-live")
    }

    @Test("Learning resources remain locked before completion and unlock with Replay CTA after completion (REQ-S03, REQ-S08, REQ-S12)")
    func resourceVisibilityAndReplayGatedOnCompletionState() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_760_000_000)
        let resources = [
            LearningResource(
                title: "Apple Vision Framework",
                urlString: "https://developer.apple.com/documentation/vision"
            ),
            LearningResource(
                title: "VNClassifyImageRequest",
                urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
            )
        ]

        let quest = Quest(
            id: "quest-lock-unlock",
            title: "Spot the Keyboard",
            questDescription: "Classify a keyboard in real time.",
            status: .published,
            publishDate: fixedNow.addingTimeInterval(-120),
            targetLabel: "keyboard",
            hintText: "Check your desk setup!",
            resources: resources,
            updatedAt: fixedNow
        )

        let repository = InMemoryQuestRepository(initialQuests: [quest])
        let viewModel = ActiveQuestsViewModel(
            repository: repository,
            nowProvider: { fixedNow }
        )

        await viewModel.loadActiveQuests()

        // Before completion: resources are locked (empty) and CTA is "Start Vision Experience" (REQ-S03)
        #expect(!viewModel.isCompleted(quest))
        #expect(viewModel.visibleResources(for: quest).isEmpty)
        #expect(viewModel.experienceActionTitle(for: quest) == "Start Vision Experience")

        // Complete the quest (REQ-S07, REQ-S08, REQ-S12)
        viewModel.markQuestCompleted(quest, confidence: 0.89)

        #expect(viewModel.isCompleted(quest))
        #expect(viewModel.achievedConfidenceByQuestID[quest.id] == 0.89)
        #expect(viewModel.visibleResources(for: quest) == resources)
        #expect(viewModel.experienceActionTitle(for: quest) == "Replay Vision Experience")
    }
}
