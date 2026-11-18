import Foundation
import SwiftData

/// Immutable local SwiftData snapshot of a Quest completed by the student (`REQ-S09`, `REQ-S10`, `REQ-S11`, `REQ-S12`, Section 5.2 of `spec.md`).
/// Once saved locally on the student's iOS device, subsequent edits or deletions of the Quest in CloudKit by a mentor never delete or overwrite this local record.
@Model
final class SavedQuest {
    /// Matches CloudKit `recordName` (`Quest.id`).
    @Attribute(.unique) var questID: String

    /// Snapshot of quest title at time of completion/save.
    var title: String

    /// Snapshot of quest description.
    var questDescription: String

    /// Snapshot of the Vision taxonomy label detected.
    var targetLabel: String

    /// The confidence score (`0.0`–`1.0`) achieved when the student completed the quest.
    var detectedConfidence: Double

    /// Optional mentor hint snapshot so the student can replay the experience offline with the original hint (`REQ-S11`, `REQ-S12`).
    var hintText: String?

    /// Timestamp when the student completed the experience.
    var completedAt: Date

    /// JSON-encoded array of `LearningResource` items (`[{ id, title, urlString }]`) to guarantee lossless SwiftData persistence across platforms.
    var resourcesJSON: String

    init(
        questID: String,
        title: String,
        questDescription: String,
        targetLabel: String,
        detectedConfidence: Double,
        hintText: String? = nil,
        completedAt: Date = .now,
        resources: [LearningResource]
    ) {
        self.questID = questID
        self.title = title
        self.questDescription = questDescription
        self.targetLabel = targetLabel
        self.detectedConfidence = min(max(detectedConfidence, 0.0), 1.0)
        self.hintText = QuestValidator.normalizedHint(hintText)
        self.completedAt = completedAt
        self.resourcesJSON = (try? QuestValidator.encodeResourcesJSON(resources)) ?? "[]"
    }

    /// Snapshot initializer capturing all quest metadata and unlocked learning resources at completion time (`REQ-S09`).
    convenience init(
        from quest: Quest,
        detectedConfidence: Double,
        completedAt: Date = .now
    ) {
        let normalized = quest.normalized()
        self.init(
            questID: normalized.id,
            title: normalized.title,
            questDescription: normalized.questDescription,
            targetLabel: normalized.targetLabel,
            detectedConfidence: detectedConfidence,
            hintText: normalized.hintText,
            completedAt: completedAt,
            resources: normalized.resources
        )
    }

    /// Decoded array of unlocked `LearningResource` items (`REQ-S08`, `REQ-S09`, `REQ-S11`).
    var resources: [LearningResource] {
        get {
            (try? QuestValidator.decodeResourcesJSON(resourcesJSON)) ?? []
        }
        set {
            resourcesJSON = (try? QuestValidator.encodeResourcesJSON(newValue)) ?? "[]"
        }
    }

    /// Reconstructs a `Quest` value from the immutable local snapshot so students can view details or replay the Vision experience even offline or after CloudKit deletion (`REQ-S10`, `REQ-S11`, `REQ-S12`).
    var asQuestSnapshot: Quest {
        Quest(
            id: questID,
            title: title,
            questDescription: questDescription,
            status: .published,
            publishDate: completedAt,
            experienceType: .visionClassification,
            targetLabel: targetLabel,
            hintText: hintText,
            resources: resources,
            updatedAt: completedAt
        )
    }

    /// Formatted confidence percentage text (e.g., `"92%"`).
    var confidencePercentageText: String {
        let percent = Int((min(max(detectedConfidence, 0.0), 1.0) * 100.0).rounded())
        return "\(percent)%"
    }
}
