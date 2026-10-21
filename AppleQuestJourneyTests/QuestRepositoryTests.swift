import Foundation
import CloudKit
import Testing
@testable import AppleQuestJourney

struct QuestRepositoryTests {

    @Test("Quest to CKRecord and back round-trip preserves all fields including optional hintText")
    func ckRecordRoundTrip() throws {
        let publishDate = Date(timeIntervalSince1970: 1_750_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_750_000_500)
        let resources = [
            LearningResource(
                id: UUID(),
                title: "VNClassifyImageRequest Documentation",
                urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
            ),
            LearningResource(
                id: UUID(),
                title: "Vision Framework Overview",
                urlString: "https://developer.apple.com/documentation/vision"
            )
        ]

        let originalQuest = Quest(
            id: "quest-roundtrip-1",
            title: "Spot the Everyday Mug",
            questDescription: "Point your camera at a mug and watch Vision classify it.",
            status: .published,
            publishDate: publishDate,
            experienceType: .visionClassification,
            targetLabel: "coffee_cup",
            hintText: "Check the kitchen counter!",
            resources: resources,
            updatedAt: updatedAt
        )

        let record = try QuestCKRecordMapper.toRecord(originalQuest)
        #expect(record.recordType == "Quest")
        #expect(record.recordID.recordName == "quest-roundtrip-1")

        let decodedQuest = try QuestCKRecordMapper.fromRecord(record)
        #expect(decodedQuest == originalQuest)

        // Verify nil hintText round-trips cleanly
        let nilHintQuest = Quest(
            id: "quest-roundtrip-2",
            title: "Find a Keyboard",
            questDescription: "Classify a keyboard.",
            status: .draft,
            publishDate: publishDate,
            experienceType: .visionClassification,
            targetLabel: "keyboard",
            hintText: "   ",
            resources: resources,
            updatedAt: updatedAt
        )

        let nilHintRecord = try QuestCKRecordMapper.toRecord(nilHintQuest)
        #expect(nilHintRecord[QuestCKRecordMapper.FieldKey.hintText] == nil)

        let decodedNilHintQuest = try QuestCKRecordMapper.fromRecord(nilHintRecord)
        #expect(decodedNilHintQuest.hintText == nil)
        #expect(decodedNilHintQuest == nilHintQuest)
    }

    @Test("Student visibility filtering excludes drafts and future-scheduled quests (REQ-S02)")
    func studentVisibilityFiltering() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let resource = LearningResource(
            title: "Vision Docs",
            urlString: "https://developer.apple.com/documentation/vision"
        )

        let draftQuest = Quest(
            id: "quest-draft",
            title: "Draft Quest",
            questDescription: "Not published yet",
            status: .draft,
            publishDate: now.addingTimeInterval(-3600),
            targetLabel: "coffee_cup",
            resources: [resource],
            updatedAt: now
        )

        let scheduledFutureQuest = Quest(
            id: "quest-scheduled",
            title: "Scheduled Future Quest",
            questDescription: "Published status, but future publishDate",
            status: .published,
            publishDate: now.addingTimeInterval(3600),
            targetLabel: "keyboard",
            resources: [resource],
            updatedAt: now
        )

        let livePastQuest = Quest(
            id: "quest-live-past",
            title: "Live Past Quest",
            questDescription: "Published 1 hour ago",
            status: .published,
            publishDate: now.addingTimeInterval(-3600),
            targetLabel: "laptop",
            resources: [resource],
            updatedAt: now
        )

        let liveExactNowQuest = Quest(
            id: "quest-live-exact",
            title: "Live Exact Now Quest",
            questDescription: "Published right now",
            status: .published,
            publishDate: now,
            targetLabel: "houseplant",
            resources: [resource],
            updatedAt: now
        )

        let repository = InMemoryQuestRepository(
            initialQuests: [draftQuest, scheduledFutureQuest, livePastQuest, liveExactNowQuest]
        )

        // Mentor sees all 4 quests (Drafts, Scheduled, and Published Live)
        let mentorQuests = try await repository.fetchAllQuestsForMentor()
        #expect(mentorQuests.count == 4)

        // Student at `now` only sees the 2 active published quests with `publishDate <= now`
        let studentQuests = try await repository.fetchPublishedQuestsForStudent(at: now)
        #expect(studentQuests.map(\.id) == ["quest-live-exact", "quest-live-past"])

        // Student 2 hours later also sees the scheduled quest once its publishDate arrives
        let futureStudentQuests = try await repository.fetchPublishedQuestsForStudent(
            at: now.addingTimeInterval(7200)
        )
        #expect(futureStudentQuests.map(\.id) == ["quest-scheduled", "quest-live-exact", "quest-live-past"])
    }

    @Test("InMemoryQuestRepository supports creating, updating, and deleting quests (REQ-M01, REQ-M03, REQ-M04)")
    func repositoryCRUDLifecycle() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let resource = LearningResource(
            title: "Vision Docs",
            urlString: "https://developer.apple.com/documentation/vision"
        )

        let repository = InMemoryQuestRepository()

        // Create Draft (REQ-M01)
        var quest = Quest(
            id: "quest-crud-1",
            title: "Initial Draft Title",
            questDescription: "Initial description",
            status: .draft,
            publishDate: now,
            targetLabel: "coffee_cup",
            hintText: "Initial hint",
            resources: [resource],
            updatedAt: now
        )
        try await repository.saveQuest(quest)

        var allQuests = try await repository.fetchAllQuestsForMentor()
        #expect(allQuests.count == 1)
        #expect(allQuests.first?.title == "Initial Draft Title")

        // Edit & Publish (REQ-M02, REQ-M03)
        quest.title = "Updated Published Title"
        quest.status = .published
        quest.targetLabel = "espresso"
        quest.updatedAt = now.addingTimeInterval(60)
        try await repository.saveQuest(quest)

        let studentQuests = try await repository.fetchPublishedQuestsForStudent(at: now.addingTimeInterval(120))
        #expect(studentQuests.count == 1)
        #expect(studentQuests.first?.title == "Updated Published Title")
        #expect(studentQuests.first?.targetLabel == "espresso")

        // Delete (REQ-M04)
        try await repository.deleteQuest(id: "quest-crud-1")
        allQuests = try await repository.fetchAllQuestsForMentor()
        #expect(allQuests.isEmpty)
    }
}
