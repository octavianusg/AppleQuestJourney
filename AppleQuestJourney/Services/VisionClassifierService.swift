import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Represents a single Vision image classification observation with its taxonomy identifier and confidence (`0.0`–`1.0`).
nonisolated struct VisionObservationItem: Identifiable, Sendable, Equatable, Hashable {
    var id: String { identifier }
    let identifier: String
    let confidence: Double

    init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = min(max(confidence, 0.0), 1.0)
    }

    /// Formatted percentage string (e.g., `"84%"`) for display in the Mentor chips and Student Developer HUD (`REQ-M07`, `REQ-S05`).
    var confidencePercentageText: String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

/// Errors thrown by `VisionClassifierService`.
nonisolated enum VisionClassifierError: LocalizedError, Equatable, Sendable {
    case invalidImageData
    case classificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "The selected image could not be decoded for Vision classification."
        case .classificationFailed(let reason):
            return "Vision classification failed: \(reason)"
        }
    }
}

/// Shared service providing `VNClassifyImageRequest` taxonomy lookup, search filtering, static image classification (`REQ-M06`, `REQ-M07`), and target match evaluation (`REQ-S05`, `REQ-S07`).
nonisolated enum VisionClassifierService {
    /// Default confidence threshold required to complete a Vision Scavenger Hunt (`REQ-S07`).
    static let defaultTargetConfidenceThreshold: Double = 0.70

    /// Cached sorted list of supported `VNClassifyImageRequest` taxonomy identifiers (`REQ-M06`).
    private static let cachedTaxonomyLabels: [String] = {
        let request = VNClassifyImageRequest()
        let identifiers = (try? request.supportedIdentifiers()) ?? []
        return Array(Set(identifiers)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }()

    /// Cached set of supported taxonomy identifiers for O(1) validation (`REQ-M05`, `REQ-M06`).
    static let supportedTaxonomyLabelSet: Set<String> = Set(cachedTaxonomyLabels)

    /// Returns all valid taxonomy identifiers supported by `VNClassifyImageRequest` (`REQ-M06`).
    static func supportedTaxonomyLabels() -> [String] {
        cachedTaxonomyLabels
    }

    /// Filters and ranks valid Vision taxonomy identifiers matching the search query (`REQ-M06`).
    /// - Parameter query: Search query string. When empty or whitespace-only, returns all supported taxonomy labels.
    static func searchTaxonomyLabels(query: String) -> [String] {
        let allLabels = supportedTaxonomyLabels()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return allLabels
        }

        // Normalize spaces to underscores so searching "coffee cup" matches "coffee_cup"
        let underscoreNormalized = trimmed.replacingOccurrences(of: " ", with: "_")

        return allLabels
            .filter { label in
                let lower = label.lowercased()
                let spaceFriendly = lower.replacingOccurrences(of: "_", with: " ")
                return lower.contains(trimmed)
                    || lower.contains(underscoreNormalized)
                    || spaceFriendly.contains(trimmed)
            }
            .sorted { lhs, rhs in
                let lhsLower = lhs.lowercased()
                let rhsLower = rhs.lowercased()

                // Exact match first
                if lhsLower == trimmed || lhsLower == underscoreNormalized { return true }
                if rhsLower == trimmed || rhsLower == underscoreNormalized { return false }

                // Prefix match second
                let lhsPrefix = lhsLower.hasPrefix(trimmed) || lhsLower.hasPrefix(underscoreNormalized)
                let rhsPrefix = rhsLower.hasPrefix(trimmed) || rhsLower.hasPrefix(underscoreNormalized)
                if lhsPrefix != rhsPrefix {
                    return lhsPrefix
                }

                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    /// Classifies a static `CGImage` off the main actor using `VNClassifyImageRequest` and returns top observations sorted by descending confidence (`REQ-M07`).
    /// - Parameters:
    ///   - cgImage: The image to classify.
    ///   - maxResults: Maximum number of top observations to return (defaults to 8).
    ///   - minimumConfidence: Minimum confidence filter (defaults to `0.01`).
    static func classifyStaticImage(
        cgImage: CGImage,
        maxResults: Int = 8,
        minimumConfidence: Double = 0.01
    ) async throws -> [VisionObservationItem] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw VisionClassifierError.classificationFailed(error.localizedDescription)
            }

            let observations = request.results ?? []
            return rankObservations(
                observations.map {
                    VisionObservationItem(
                        identifier: $0.identifier,
                        confidence: Double($0.confidence)
                    )
                },
                maxResults: maxResults,
                minimumConfidence: minimumConfidence
            )
        }.value
    }

    /// Convenience helper that decodes raw image `Data` into a `CGImage` and classifies it (`REQ-M07`).
    static func classifyImageData(
        _ data: Data,
        maxResults: Int = 8,
        minimumConfidence: Double = 0.01
    ) async throws -> [VisionObservationItem] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VisionClassifierError.invalidImageData
        }
        return try await classifyStaticImage(
            cgImage: cgImage,
            maxResults: maxResults,
            minimumConfidence: minimumConfidence
        )
    }

    /// Filters, sorts by descending confidence, and caps a sequence of `VisionObservationItem` values (`REQ-M07`, `REQ-S05`).
    static func rankObservations(
        _ items: [VisionObservationItem],
        maxResults: Int = 8,
        minimumConfidence: Double = 0.0
    ) -> [VisionObservationItem] {
        guard maxResults > 0 else { return [] }
        return items
            .filter { $0.confidence >= minimumConfidence }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.identifier.localizedCaseInsensitiveCompare(rhs.identifier) == .orderedAscending
            }
            .prefix(maxResults)
            .map { $0 }
    }

    /// Evaluates whether any observation matches `targetLabel` (case-insensitive) at or above `threshold` (`REQ-S07`).
    /// Returns the matching `VisionObservationItem` if a match is found.
    static func matchingObservation(
        in observations: [VisionObservationItem],
        targetLabel: String,
        threshold: Double = defaultTargetConfidenceThreshold
    ) -> VisionObservationItem? {
        let normalizedTarget = targetLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTarget.isEmpty else { return nil }
        return observations.first { item in
            item.identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTarget
                && item.confidence >= threshold
        }
    }
}
