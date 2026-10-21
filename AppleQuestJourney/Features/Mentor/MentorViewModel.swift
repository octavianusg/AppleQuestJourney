import Foundation
import Observation

/// Sidebar filter categories for the macOS Mentor Dashboard (`REQ-M01`–`REQ-M04`).
nonisolated enum MentorQuestFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Quests"
    case drafts = "Drafts"
    case scheduled = "Scheduled"
    case publishedLive = "Published Live"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:
            return "tray.full"
        case .drafts:
            return "doc.text"
        case .scheduled:
            return "calendar.badge.clock"
        case .publishedLive:
            return "antenna.radiowaves.left.and.right"
        }
    }
}

/// Computed publication state of a `Quest` relative to a reference timestamp (`now`).
nonisolated enum MentorQuestDisplayState: String, Equatable, Sendable {
    case draft = "Draft"
    case scheduled = "Scheduled"
    case publishedLive = "Published Live"
}

extension Quest {
    /// Determines whether this quest is currently a Draft, Scheduled for the future, or Published Live (`REQ-M01`, `REQ-M02`, `REQ-S02`).
    nonisolated func displayState(at now: Date = .now) -> MentorQuestDisplayState {
        switch status {
        case .draft:
            return .draft
        case .published:
            return publishDate > now ? .scheduled : .publishedLive
        }
    }
}

/// Manages Mentor quest authoring, filtering, and CloudKit CRUD operations (`REQ-M01`, `REQ-M02`, `REQ-M03`, `REQ-M04`).
@Observable
@MainActor
final class MentorViewModel {
    private let repository: any QuestRepositoryProtocol
    private let nowProvider: @Sendable () -> Date

    var quests: [Quest] = []
    var selectedFilter: MentorQuestFilter = .all
    var selectedQuestID: String?
    var searchQuery: String = ""
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var statusBannerMessage: String?

    init(
        repository: any QuestRepositoryProtocol = CloudKitQuestRepository(),
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.nowProvider = nowProvider
    }

    /// Currently selected `Quest` from `quests`, if any.
    var selectedQuest: Quest? {
        guard let selectedQuestID else { return nil }
        return quests.first { $0.id == selectedQuestID }
    }

    /// Quests filtered by `selectedFilter` and `searchQuery`, sorted by `updatedAt` descending.
    var filteredQuests: [Quest] {
        let now = nowProvider()
        let trimmedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return quests
            .filter { quest in
                let matchesFilter: Bool
                switch selectedFilter {
                case .all:
                    matchesFilter = true
                case .drafts:
                    matchesFilter = quest.displayState(at: now) == .draft
                case .scheduled:
                    matchesFilter = quest.displayState(at: now) == .scheduled
                case .publishedLive:
                    matchesFilter = quest.displayState(at: now) == .publishedLive
                }

                guard matchesFilter else { return false }
                guard !trimmedSearch.isEmpty else { return true }

                return quest.title.lowercased().contains(trimmedSearch)
                    || quest.questDescription.lowercased().contains(trimmedSearch)
                    || quest.targetLabel.lowercased().contains(trimmedSearch)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Returns the number of quests matching a given `MentorQuestFilter`.
    func count(for filter: MentorQuestFilter) -> Int {
        let now = nowProvider()
        switch filter {
        case .all:
            return quests.count
        case .drafts:
            return quests.filter { $0.displayState(at: now) == .draft }.count
        case .scheduled:
            return quests.filter { $0.displayState(at: now) == .scheduled }.count
        case .publishedLive:
            return quests.filter { $0.displayState(at: now) == .publishedLive }.count
        }
    }

    /// Loads all quests from the repository (`REQ-M01`–`REQ-M04`).
    func loadQuests() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await repository.fetchAllQuestsForMentor()
            quests = loaded.sorted { $0.updatedAt > $1.updatedAt }
            if selectedQuestID == nil || !quests.contains(where: { $0.id == selectedQuestID }) {
                selectedQuestID = filteredQuests.first?.id ?? quests.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates a new unsaved draft quest template with a valid default Vision taxonomy label and resource placeholder.
    func makeNewQuestTemplate() -> Quest {
        let defaultLabel = VisionClassifierService.supportedTaxonomyLabels().first ?? "coffee_cup"
        let now = nowProvider()
        return Quest(
            id: UUID().uuidString,
            title: "",
            questDescription: "",
            status: .draft,
            publishDate: now,
            experienceType: .visionClassification,
            targetLabel: defaultLabel,
            hintText: nil,
            resources: [
                LearningResource(
                    title: "VNClassifyImageRequest — Apple Developer Documentation",
                    urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
                )
            ],
            updatedAt: now
        )
    }

    /// Saves a quest as a Draft (`status == .draft`) to the repository (`REQ-M01`, `REQ-M03`).
    @discardableResult
    func saveAsDraft(_ quest: Quest) async throws -> Quest {
        var draftQuest = quest.normalized()
        draftQuest.status = .draft
        draftQuest.updatedAt = nowProvider()
        return try await persistQuest(draftQuest, banner: "Saved '\(draftQuest.title)' as Draft.")
    }

    /// Publishes or schedules a quest (`status == .published`) with the specified `publishDate` (`REQ-M02`, `REQ-M03`).
    @discardableResult
    func publishQuest(_ quest: Quest, publishDate: Date? = nil) async throws -> Quest {
        var publishedQuest = quest.normalized()
        publishedQuest.status = .published
        if let publishDate {
            publishedQuest.publishDate = publishDate
        }
        let now = nowProvider()
        publishedQuest.updatedAt = now

        let actionVerb = publishedQuest.publishDate > now ? "Scheduled" : "Published"
        return try await persistQuest(publishedQuest, banner: "\(actionVerb) '\(publishedQuest.title)'.")
    }

    /// Deletes a quest from the repository and removes it from the local list (`REQ-M04`).
    func deleteQuest(_ quest: Quest) async throws {
        try await deleteQuest(id: quest.id)
    }

    /// Deletes a quest by its ID from the repository (`REQ-M04`).
    func deleteQuest(id: String) async throws {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await repository.deleteQuest(id: id)
            quests.removeAll { $0.id == id }
            if selectedQuestID == id {
                selectedQuestID = filteredQuests.first?.id ?? quests.first?.id
            }
            statusBannerMessage = "Quest deleted."
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func persistQuest(_ quest: Quest, banner: String) async throws -> Quest {
        let validationErrors = QuestValidator.validate(
            quest,
            allowedTaxonomyLabels: VisionClassifierService.supportedTaxonomyLabelSet
        )
        if let firstError = validationErrors.first {
            errorMessage = firstError.localizedDescription
            throw firstError
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let saved = try await repository.saveQuest(quest)
            if let existingIndex = quests.firstIndex(where: { $0.id == saved.id }) {
                quests[existingIndex] = saved
            } else {
                quests.insert(saved, at: 0)
            }
            quests.sort { $0.updatedAt > $1.updatedAt }
            selectedQuestID = saved.id
            statusBannerMessage = banner
            return saved
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
