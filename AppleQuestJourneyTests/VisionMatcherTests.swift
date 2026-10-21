import Foundation
import Testing
@testable import AppleQuestJourney

@Suite("Vision Scavenger Hunt Matcher & Developer HUD Tests")
@MainActor
struct VisionMatcherTests {
    @Test("Observation matching targetLabel (case-insensitive) with confidence >= 0.70 triggers completion (REQ-S05, REQ-S07)")
    func observationAtOrAboveThresholdTriggersCompletion() {
        let manager = LiveCameraManager(
            targetLabel: "coffee_cup",
            hintText: "Check the kitchen counter!",
            confidenceThreshold: 0.70
        )

        #expect(manager.requestClassName == "VNClassifyImageRequest")
        #expect(manager.targetLabel == "coffee_cup")
        #expect(!manager.isCompleted)
        #expect(manager.matchedObservation == nil)

        let incomingObservations = [
            VisionObservationItem(identifier: "Coffee_Cup", confidence: 0.84),
            VisionObservationItem(identifier: "mug", confidence: 0.61),
            VisionObservationItem(identifier: "tableware", confidence: 0.42),
            VisionObservationItem(identifier: "indoor", confidence: 0.19)
        ]

        let matched = manager.processObservations(incomingObservations)

        // Top 3 observations are populated in descending confidence order for the Developer HUD (REQ-S05)
        #expect(manager.topObservations.count == 3)
        #expect(manager.topObservations.map(\.identifier) == ["Coffee_Cup", "mug", "tableware"])

        // Target label match at 0.84 >= 0.70 triggers completion (REQ-S07)
        #expect(manager.isCompleted)
        #expect(matched?.identifier == "Coffee_Cup")
        #expect(matched?.confidence == 0.84)
        #expect(manager.matchedObservation?.confidence == 0.84)
    }

    @Test("Observation matching targetLabel with confidence < 0.70 updates Developer HUD without triggering completion (REQ-S05, REQ-S07)")
    func observationBelowThresholdUpdatesHUDOnly() {
        let manager = LiveCameraManager(
            targetLabel: "keyboard",
            hintText: nil,
            confidenceThreshold: 0.70
        )

        let lowConfidenceObservations = [
            VisionObservationItem(identifier: "keyboard", confidence: 0.68),
            VisionObservationItem(identifier: "laptop", confidence: 0.55),
            VisionObservationItem(identifier: "electronics", confidence: 0.31),
            VisionObservationItem(identifier: "desk", confidence: 0.12)
        ]

        let matched = manager.processObservations(lowConfidenceObservations)

        // Developer HUD still updates with Top 3 observations (REQ-S05)
        #expect(manager.topObservations.count == 3)
        #expect(manager.topObservations.first?.identifier == "keyboard")
        #expect(manager.topObservations.first?.confidencePercentageText == "68%")

        // Does NOT trigger completion because 0.68 < 0.70 (REQ-S07)
        #expect(matched == nil)
        #expect(!manager.isCompleted)
        #expect(manager.matchedObservation == nil)
    }

    @Test("Mentor hint button visibility and toggle state match quest.hintText presence (REQ-S06)")
    func mentorHintVisibilityMatchesHintText() {
        let questWithHint = Quest(
            id: "quest-with-hint",
            title: "Spot the Mug",
            questDescription: "Find a mug.",
            status: .published,
            publishDate: .now,
            targetLabel: "coffee_cup",
            hintText: "  Look near the espresso machine!  ",
            resources: [LearningResource(title: "Vision Docs", urlString: "https://developer.apple.com/documentation/vision")]
        )

        let managerWithHint = LiveCameraManager(quest: questWithHint)
        #expect(managerWithHint.hasHint)
        #expect(managerWithHint.normalizedHint == "Look near the espresso machine!")
        #expect(!managerWithHint.isHintRevealed)

        managerWithHint.toggleHint()
        #expect(managerWithHint.isHintRevealed)

        let questWithoutHint = Quest(
            id: "quest-no-hint",
            title: "Spot the Keyboard",
            questDescription: "Find a keyboard.",
            status: .published,
            publishDate: .now,
            targetLabel: "keyboard",
            hintText: "   ",
            resources: [LearningResource(title: "Vision Docs", urlString: "https://developer.apple.com/documentation/vision")]
        )

        let managerWithoutHint = LiveCameraManager(quest: questWithoutHint)
        #expect(!managerWithoutHint.hasHint)
        #expect(managerWithoutHint.normalizedHint == nil)

        managerWithoutHint.toggleHint()
        #expect(!managerWithoutHint.isHintRevealed)
    }
}
