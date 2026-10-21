import Foundation
import Testing
@testable import AppleQuestJourney

struct QuestValidationTests {

    @Test("Valid quest passes validation")
    func validQuestPassesValidation() {
        let resource = LearningResource(
            title: "VNClassifyImageRequest Documentation",
            urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
        )
        let quest = Quest(
            title: "Spot the Everyday Mug",
            questDescription: "Point your camera at a coffee mug to see Vision classify it in real time.",
            status: .draft,
            targetLabel: "coffee_cup",
            hintText: "Check the kitchen counter!",
            resources: [resource]
        )

        let allowedLabels: Set<String> = ["coffee_cup", "keyboard", "laptop"]
        let errors = QuestValidator.validate(quest, allowedTaxonomyLabels: allowedLabels)
        #expect(errors.isEmpty)
        #expect(QuestValidator.isValid(quest, allowedTaxonomyLabels: allowedLabels))
    }

    @Test("Empty title or empty target label fails validation (REQ-M05)")
    func emptyTitleOrTargetLabelFailsValidation() {
        let validResource = LearningResource(
            title: "Vision Framework Overview",
            urlString: "https://developer.apple.com/documentation/vision"
        )

        let emptyTitleQuest = Quest(
            title: "   ",
            questDescription: "Learn Vision classification.",
            targetLabel: "coffee_cup",
            resources: [validResource]
        )
        let titleErrors = QuestValidator.validate(emptyTitleQuest)
        #expect(titleErrors.contains(.emptyTitle))
        #expect(!QuestValidator.isValid(emptyTitleQuest))

        let emptyTargetQuest = Quest(
            title: "Find a Keyboard",
            questDescription: "Learn Vision classification.",
            targetLabel: "  \n ",
            resources: [validResource]
        )
        let targetErrors = QuestValidator.validate(emptyTargetQuest)
        #expect(targetErrors.contains(.emptyTargetLabel))
        #expect(!QuestValidator.isValid(emptyTargetQuest))

        let unsupportedTargetQuest = Quest(
            title: "Find a Dragon",
            questDescription: "Learn Vision classification.",
            targetLabel: "mythical_dragon_xyz",
            resources: [validResource]
        )
        let taxonomyErrors = QuestValidator.validate(
            unsupportedTargetQuest,
            allowedTaxonomyLabels: ["coffee_cup", "keyboard"]
        )
        #expect(taxonomyErrors.contains(.invalidTargetLabel("mythical_dragon_xyz")))
    }

    @Test("Malformed or non-HTTP URLs and empty resources fail validation (REQ-M05)")
    func malformedURLsFailValidation() {
        let noResourceQuest = Quest(
            title: "Spot a Mug",
            questDescription: "Description",
            targetLabel: "coffee_cup",
            resources: []
        )
        #expect(QuestValidator.validate(noResourceQuest).contains(.noResources))

        let invalidURLStrings = [
            "not-a-url",
            "ftp://example.com/resource",
            "file:///Users/test/file.pdf",
            "http://",
            "https://",
            "   "
        ]

        for badURL in invalidURLStrings {
            let resource = LearningResource(title: "Doc", urlString: badURL)
            #expect(resource.validURL == nil, "Expected \(badURL) to be rejected")

            let quest = Quest(
                title: "Spot a Mug",
                questDescription: "Description",
                targetLabel: "coffee_cup",
                resources: [resource]
            )
            let errors = QuestValidator.validate(quest)
            #expect(errors.contains(.invalidResourceURL(resource.id, badURL)))
            #expect(!QuestValidator.isValid(quest))
        }

        let validHTTP = LearningResource(title: "Example HTTP", urlString: "http://example.com/ guide".replacingOccurrences(of: " ", with: ""))
        let validHTTPS = LearningResource(title: "Apple Docs", urlString: "https://developer.apple.com/documentation/vision")
        #expect(validHTTP.validURL != nil)
        #expect(validHTTPS.validURL != nil)
    }

    @Test("Blank hintText normalizes to nil while non-empty hintText trims whitespace (REQ-M08)")
    func blankHintNormalizesToNil() {
        let blankHintQuest = Quest(
            title: "Spot a Mug",
            questDescription: "Description",
            targetLabel: "coffee_cup",
            hintText: "   \n\t  ",
            resources: [LearningResource(title: "Docs", urlString: "https://developer.apple.com")]
        )
        #expect(blankHintQuest.hintText == nil)

        let nilHintQuest = Quest(
            title: "Spot a Mug",
            questDescription: "Description",
            targetLabel: "coffee_cup",
            hintText: nil,
            resources: [LearningResource(title: "Docs", urlString: "https://developer.apple.com")]
        )
        #expect(nilHintQuest.hintText == nil)

        let validHintQuest = Quest(
            title: "Spot a Mug",
            questDescription: "Description",
            targetLabel: "coffee_cup",
            hintText: "  Look near the coffee machine!  ",
            resources: [LearningResource(title: "Docs", urlString: "https://developer.apple.com")]
        )
        #expect(validHintQuest.hintText == "Look near the coffee machine!")
    }

    @Test("LearningResource and Quest JSON encoding/decoding round-trips losslessly")
    func learningResourceJSONRoundTrip() throws {
        let resources = [
            LearningResource(
                id: UUID(),
                title: "Classifying Images for Categorization and Search",
                urlString: "https://developer.apple.com/documentation/vision/classifying_images_for_categorization_and_search"
            ),
            LearningResource(
                id: UUID(),
                title: "WWDC Session: Explore Computer Vision APIs",
                urlString: "https://developer.apple.com/videos/play/wwdc2019/222/"
            )
        ]

        let data = try JSONEncoder().encode(resources)
        let decoded = try JSONDecoder().decode([LearningResource].self, from: data)
        #expect(decoded == resources)
    }
}
