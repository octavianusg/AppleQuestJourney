import Foundation
import CoreGraphics
import Testing
@testable import AppleQuestJourney

struct VisionTaxonomyTests {

    @Test("supportedTaxonomyLabels() returns a non-empty sorted list of valid Vision identifiers (REQ-M06)")
    func supportedTaxonomyLabelsAreNonEmptyAndValid() {
        let labels = VisionClassifierService.supportedTaxonomyLabels()
        #expect(!labels.isEmpty)
        #expect(VisionClassifierService.supportedTaxonomyLabelSet.count == labels.count)

        // Verify labels contain no empty strings
        #expect(labels.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Test("searchTaxonomyLabels(query:) only returns identifiers present in supportedTaxonomyLabels() (REQ-M06)")
    func searchTaxonomyLabelsSubsetsSupportedIdentifiers() throws {
        let allLabels = VisionClassifierService.supportedTaxonomyLabels()
        let allowedSet = VisionClassifierService.supportedTaxonomyLabelSet
        #expect(!allLabels.isEmpty)

        // Empty or whitespace query returns all supported identifiers
        let emptyQueryResults = VisionClassifierService.searchTaxonomyLabels(query: "   ")
        #expect(emptyQueryResults == allLabels)

        // Pick a real identifier from the built-in Vision taxonomy to search for
        let sampleLabel = try #require(allLabels.first)
        let prefixFragment = String(sampleLabel.prefix(min(3, sampleLabel.count)))

        let searchResults = VisionClassifierService.searchTaxonomyLabels(query: prefixFragment)
        #expect(!searchResults.isEmpty)
        #expect(searchResults.contains(sampleLabel))
        #expect(searchResults.allSatisfy { allowedSet.contains($0) })

        //Exact query should rank the exact match first
        let exactResults = VisionClassifierService.searchTaxonomyLabels(query: sampleLabel.uppercased())
        #expect(exactResults.first == sampleLabel)
        #expect(exactResults.allSatisfy { allowedSet.contains($0) })

        // Non-existent query returns empty list
        let bogusResults = VisionClassifierService.searchTaxonomyLabels(query: "zz_impossible_taxonomy_label_99999")
        #expect(bogusResults.isEmpty)
    }

    @Test("classifyStaticImage(cgImage:) executes asynchronously and returns observations sorted by descending confidence (REQ-M07)")
    func classifyStaticImageReturnsSortedObservations() async throws {
        let cgImage = try #require(Self.makeTestCGImage(width: 128, height: 128))
        let supportedSet = VisionClassifierService.supportedTaxonomyLabelSet

        let observations = try await VisionClassifierService.classifyStaticImage(
            cgImage: cgImage,
            maxResults: 10,
            minimumConfidence: 0.0
        )

        // Verify descending confidence order and valid taxonomy identifiers
        for index in observations.indices {
            let item = observations[index]
            #expect(item.confidence >= 0.0 && item.confidence <= 1.0)
            #expect(supportedSet.contains(item.identifier))
            if index > 0 {
                #expect(observations[index - 1].confidence >= item.confidence)
            }
        }

        // Also verify deterministic ranking helper behavior on synthetic observations
        let unsorted = [
            VisionObservationItem(identifier: "keyboard", confidence: 0.42),
            VisionObservationItem(identifier: "coffee_cup", confidence: 0.88),
            VisionObservationItem(identifier: "laptop", confidence: 0.71),
            VisionObservationItem(identifier: "desk", confidence: 0.005)
        ]
        let ranked = VisionClassifierService.rankObservations(unsorted, maxResults: 3, minimumConfidence: 0.01)
        #expect(ranked.map(\.identifier) == ["coffee_cup", "laptop", "keyboard"])
        #expect(ranked.first?.confidencePercentageText == "88%")
    }

    /// Creates a simple RGBA `CGImage` in memory for testing `classifyStaticImage(cgImage:)`.
    private static func makeTestCGImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setFillColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1.0)
        context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return context.makeImage()
    }
}
