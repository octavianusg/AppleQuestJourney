import Foundation

/// Represents the publication lifecycle status of a Quest (`REQ-M01`, `REQ-M02`).
nonisolated enum QuestStatus: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case draft = "draft"
    case published = "published"
}

/// Extensible identifier for the interactive framework experience wrapped by a Quest.
nonisolated enum ExperienceType: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case visionClassification = "vision_classification"
}

/// An external learning resource URL (e.g., Apple Developer Documentation, WWDC session, article) attached to a Quest.
nonisolated struct LearningResource: Identifiable, Codable, Sendable, Equatable, Hashable {
    var id: UUID
    var title: String
    var urlString: String

    init(id: UUID = UUID(), title: String, urlString: String) {
        self.id = id
        self.title = title
        self.urlString = urlString
    }

    /// Returns a valid `URL` only if `urlString` trims to a well-formed `http` or `https` URL with a non-empty host (`REQ-M05`).
    var validURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = components.url else {
            return nil
        }
        return url
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validURL != nil
    }
}

/// Core domain model representing a single-experience Quest configured by a Mentor and played by Student Developers.
nonisolated struct Quest: Identifiable, Codable, Sendable, Equatable, Hashable {
    var id: String
    var title: String
    var questDescription: String
    var status: QuestStatus
    var publishDate: Date
    var experienceType: ExperienceType
    var targetLabel: String
    var hintText: String?
    var resources: [LearningResource]
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        questDescription: String,
        status: QuestStatus = .draft,
        publishDate: Date = .now,
        experienceType: ExperienceType = .visionClassification,
        targetLabel: String,
        hintText: String? = nil,
        resources: [LearningResource] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.questDescription = questDescription
        self.status = status
        self.publishDate = publishDate
        self.experienceType = experienceType
        self.targetLabel = targetLabel
        self.hintText = QuestValidator.normalizedHint(hintText)
        self.resources = resources
        self.updatedAt = updatedAt
    }

    /// Returns a copy with normalized optional fields (e.g., blank `hintText` normalized to `nil` per `REQ-M08`).
    func normalized() -> Quest {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.questDescription = questDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.targetLabel = targetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.hintText = QuestValidator.normalizedHint(hintText)
        return copy
    }
}

/// Specific validation errors surfaced inline in the Mentor Quest Editor (`REQ-M05`).
nonisolated enum QuestValidationError: LocalizedError, Equatable, Sendable {
    case emptyTitle
    case emptyTargetLabel
    case invalidTargetLabel(String)
    case noResources
    case emptyResourceTitle(UUID)
    case invalidResourceURL(UUID, String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Quest title is required."
        case .emptyTargetLabel:
            return "A target Vision taxonomy label is required."
        case .invalidTargetLabel(let label):
            return "'\(label)' is not a supported Vision taxonomy identifier."
        case .noResources:
            return "At least one learning resource URL is required."
        case .emptyResourceTitle:
            return "Every learning resource must have a title."
        case .invalidResourceURL(_, let urlString):
            return "'\(urlString)' must be a valid http or https URL."
        }
    }
}

/// Validates Quest configurations before saving or publishing (`REQ-M05`, `REQ-M08`).
nonisolated enum QuestValidator {
    /// Normalizes an optional hint string so empty or whitespace-only strings become `nil` (`REQ-M08`).
    static func normalizedHint(_ rawHint: String?) -> String? {
        guard let trimmed = rawHint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Validates whether a URL string uses `http` or `https` and contains a non-empty host (`REQ-M05`).
    static func isValidHTTPURL(_ urlString: String) -> Bool {
        LearningResource(title: "Check", urlString: urlString).validURL != nil
    }

    /// Returns all validation errors for a given `Quest` and optional set of allowed Vision taxonomy identifiers (`REQ-M05`).
    static func validate(
        _ quest: Quest,
        allowedTaxonomyLabels: Set<String>? = nil
    ) -> [QuestValidationError] {
        var errors: [QuestValidationError] = []

        let trimmedTitle = quest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errors.append(.emptyTitle)
        }

        let trimmedTarget = quest.targetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTarget.isEmpty {
            errors.append(.emptyTargetLabel)
        } else if let allowedTaxonomyLabels, !allowedTaxonomyLabels.contains(trimmedTarget) {
            errors.append(.invalidTargetLabel(trimmedTarget))
        }

        if quest.resources.isEmpty {
            errors.append(.noResources)
        } else {
            for resource in quest.resources {
                if resource.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(.emptyResourceTitle(resource.id))
                }
                if resource.validURL == nil {
                    errors.append(.invalidResourceURL(resource.id, resource.urlString))
                }
            }
        }

        return errors
    }

    /// Convenience boolean check for enabling/disabling Save and Publish actions (`REQ-M05`).
    static func isValid(
        _ quest: Quest,
        allowedTaxonomyLabels: Set<String>? = nil
    ) -> Bool {
        validate(quest, allowedTaxonomyLabels: allowedTaxonomyLabels).isEmpty
    }
}
