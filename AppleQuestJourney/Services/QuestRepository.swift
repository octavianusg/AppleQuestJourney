import Foundation
import CloudKit

/// Errors thrown by `QuestRepositoryProtocol` implementations.
nonisolated enum QuestRepositoryError: LocalizedError, Equatable, Sendable {
    case invalidRecordField(String)
    case questNotFound(String)
    case encodingFailed
    case decodingFailed
    case cloudKitFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidRecordField(let field):
            return "CloudKit record is missing or has an invalid '\(field)' field."
        case .questNotFound(let id):
            return "Quest with ID '\(id)' could not be found."
        case .encodingFailed:
            return "Failed to encode LearningResource list to JSON."
        case .decodingFailed:
            return "Failed to decode LearningResource list from JSON."
        case .cloudKitFailure(let message):
            return "CloudKit error: \(message)"
        }
    }
}

/// Abstract repository for managing `Quest` records across Mentor (macOS) and Student (iOS) experiences (`REQ-M01`–`REQ-M04`, `REQ-S02`).
nonisolated protocol QuestRepositoryProtocol: Sendable {
    /// Fetches all quests (Drafts, Scheduled, and Published Live) for the Mentor dashboard on macOS.
    func fetchAllQuestsForMentor() async throws -> [Quest]

    /// Fetches only quests with `status == .published` and `publishDate <= now` for the Student feed on iOS (`REQ-S02`).
    func fetchPublishedQuestsForStudent(at now: Date) async throws -> [Quest]

    /// Creates or updates a quest (`REQ-M01`, `REQ-M02`, `REQ-M03`).
    @discardableResult
    func saveQuest(_ quest: Quest) async throws -> Quest

    /// Deletes an existing quest by its identifier (`REQ-M04`).
    func deleteQuest(id: String) async throws
}

/// Maps between domain `Quest` models and CloudKit `CKRecord` instances (`recordType = "Quest"`).
nonisolated enum QuestCKRecordMapper {
    static let recordType = "Quest"

    enum FieldKey {
        static let title = "title"
        static let questDescription = "questDescription"
        static let status = "status"
        static let publishDate = "publishDate"
        static let experienceType = "experienceType"
        static let targetLabel = "targetLabel"
        static let hintText = "hintText"
        static let resourcesJSON = "resourcesJSON"
        static let updatedAt = "updatedAt"
    }

    /// Populates an existing or newly created `CKRecord` with fields from a `Quest` (`REQ-M01`, `REQ-M03`).
    @discardableResult
    static func apply(_ quest: Quest, to record: CKRecord) throws -> CKRecord {
        let normalized = quest.normalized()
        let encoder = JSONEncoder()
        guard let resourcesData = try? encoder.encode(normalized.resources),
              let resourcesJSON = String(data: resourcesData, encoding: .utf8) else {
            throw QuestRepositoryError.encodingFailed
        }

        record[FieldKey.title] = normalized.title as CKRecordValue
        record[FieldKey.questDescription] = normalized.questDescription as CKRecordValue
        record[FieldKey.status] = normalized.status.rawValue as CKRecordValue
        record[FieldKey.publishDate] = normalized.publishDate as CKRecordValue
        record[FieldKey.experienceType] = normalized.experienceType.rawValue as CKRecordValue
        record[FieldKey.targetLabel] = normalized.targetLabel as CKRecordValue
        record[FieldKey.hintText] = normalized.hintText as CKRecordValue?
        record[FieldKey.resourcesJSON] = resourcesJSON as CKRecordValue
        record[FieldKey.updatedAt] = normalized.updatedAt as CKRecordValue

        return record
    }

    /// Converts a `Quest` into a new `CKRecord` with `recordType = "Quest"`.
    static func toRecord(_ quest: Quest) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: quest.id)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        return try apply(quest, to: record)
    }

    /// Reconstructs a domain `Quest` from a `CKRecord`.
    static func fromRecord(_ record: CKRecord) throws -> Quest {
        guard let title = record[FieldKey.title] as? String else {
            throw QuestRepositoryError.invalidRecordField(FieldKey.title)
        }
        guard let questDescription = record[FieldKey.questDescription] as? String else {
            throw QuestRepositoryError.invalidRecordField(FieldKey.questDescription)
        }
        guard let statusRaw = record[FieldKey.status] as? String,
              let status = QuestStatus(rawValue: statusRaw) else {
            throw QuestRepositoryError.invalidRecordField(FieldKey.status)
        }
        guard let publishDate = record[FieldKey.publishDate] as? Date else {
            throw QuestRepositoryError.invalidRecordField(FieldKey.publishDate)
        }
        guard let experienceRaw = record[FieldKey.experienceType] as? String,
              let experienceType = ExperienceType(rawValue: experienceRaw) else {
            throw QuestRepositoryError.invalidRecordField(FieldKey.experienceType)
        }
        guard let targetLabel = record[FieldKey.targetLabel] as? String else {
            throw QuestRepositoryError.invalidRecordField(FieldKey.targetLabel)
        }
        guard let resourcesJSON = record[FieldKey.resourcesJSON] as? String,
              let resourcesData = resourcesJSON.data(using: .utf8) else {
            throw QuestRepositoryError.invalidRecordField(FieldKey.resourcesJSON)
        }

        let decoder = JSONDecoder()
        guard let resources = try? decoder.decode([LearningResource].self, from: resourcesData) else {
            throw QuestRepositoryError.decodingFailed
        }

        let hintText = record[FieldKey.hintText] as? String
        let updatedAt = (record[FieldKey.updatedAt] as? Date) ?? record.modificationDate ?? publishDate

        return Quest(
            id: record.recordID.recordName,
            title: title,
            questDescription: questDescription,
            status: status,
            publishDate: publishDate,
            experienceType: experienceType,
            targetLabel: targetLabel,
            hintText: hintText,
            resources: resources,
            updatedAt: updatedAt
        )
    }

    /// Evaluates whether a quest is eligible to be shown to students at the given timestamp (`REQ-S02`).
    static func isVisibleToStudent(_ quest: Quest, at now: Date) -> Bool {
        quest.status == .published && quest.publishDate <= now
    }

    /// Builds the CloudKit `NSPredicate` for querying active published quests (`REQ-S02`).
    static func studentVisibilityPredicate(at now: Date) -> NSPredicate {
        NSPredicate(
            format: "%K == %@ AND %K <= %@",
            FieldKey.status,
            QuestStatus.published.rawValue,
            FieldKey.publishDate,
            now as NSDate
        )
    }
}

/// Live CloudKit implementation backed by `CKContainer.default().publicCloudDatabase`.
nonisolated final class CloudKitQuestRepository: QuestRepositoryProtocol, Sendable {
    private let containerIdentifier: String?

    init(containerIdentifier: String? = nil) {
        self.containerIdentifier = containerIdentifier
    }

    private var database: CKDatabase {
        if let containerIdentifier {
            return CKContainer(identifier: containerIdentifier).publicCloudDatabase
        }
        return CKContainer.default().publicCloudDatabase
    }

    func fetchAllQuestsForMentor() async throws -> [Quest] {
        let query = CKQuery(recordType: QuestCKRecordMapper.recordType, predicate: NSPredicate(value: true))

        do {
            let (matchResults, _) = try await database.records(matching: query)
            var quests: [Quest] = []
            for (_, result) in matchResults {
                let record = try result.get()
                let quest = try QuestCKRecordMapper.fromRecord(record)
                quests.append(quest)
            }
            return quests.sorted { $0.updatedAt > $1.updatedAt }
        } catch let error as CKError where error.code == .unknownItem {
            // If no "Quest" record has been saved to CloudKit yet, the record type doesn't exist in the schema yet.
            return []
        }
    }

    func fetchPublishedQuestsForStudent(at now: Date = .now) async throws -> [Quest] {
        let predicate = QuestCKRecordMapper.studentVisibilityPredicate(at: now)
        let query = CKQuery(recordType: QuestCKRecordMapper.recordType, predicate: predicate)

        do {
            let (matchResults, _) = try await database.records(matching: query)
            var quests: [Quest] = []
            for (_, result) in matchResults {
                let record = try result.get()
                let quest = try QuestCKRecordMapper.fromRecord(record)
                if QuestCKRecordMapper.isVisibleToStudent(quest, at: now) {
                    quests.append(quest)
                }
            }
            return quests.sorted { $0.publishDate > $1.publishDate }
        } catch let error as CKError where error.code == .unknownItem {
            // If no "Quest" record has been saved to CloudKit yet, return an empty feed gracefully.
            return []
        }
    }

    @discardableResult
    func saveQuest(_ quest: Quest) async throws -> Quest {
        let recordID = CKRecord.ID(recordName: quest.id)
        let existingRecord = try? await database.record(for: recordID)
        let recordToSave = existingRecord ?? CKRecord(recordType: QuestCKRecordMapper.recordType, recordID: recordID)

        var updatedQuest = quest.normalized()
        updatedQuest.updatedAt = .now
        try QuestCKRecordMapper.apply(updatedQuest, to: recordToSave)

        let savedRecord = try await database.save(recordToSave)
        return try QuestCKRecordMapper.fromRecord(savedRecord)
    }

    func deleteQuest(id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        _ = try await database.deleteRecord(withID: recordID)
    }
}

/// Deterministic in-memory implementation of `QuestRepositoryProtocol` for SwiftUI Previews and unit tests.
actor InMemoryQuestRepository: QuestRepositoryProtocol {
    private var storage: [String: Quest] = [:]
    private var simulatedError: QuestRepositoryError?

    init(initialQuests: [Quest] = [], simulatedError: QuestRepositoryError? = nil) {
        for quest in initialQuests {
            self.storage[quest.id] = quest.normalized()
        }
        self.simulatedError = simulatedError
    }

    func setSimulatedError(_ error: QuestRepositoryError?) {
        self.simulatedError = error
    }

    func fetchAllQuestsForMentor() async throws -> [Quest] {
        if let simulatedError {
            throw simulatedError
        }
        return storage.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchPublishedQuestsForStudent(at now: Date = .now) async throws -> [Quest] {
        if let simulatedError {
            throw simulatedError
        }
        return storage.values
            .filter { QuestCKRecordMapper.isVisibleToStudent($0, at: now) }
            .sorted { $0.publishDate > $1.publishDate }
    }

    @discardableResult
    func saveQuest(_ quest: Quest) async throws -> Quest {
        if let simulatedError {
            throw simulatedError
        }
        let normalized = quest.normalized()
        storage[normalized.id] = normalized
        return normalized
    }

    func deleteQuest(id: String) async throws {
        if let simulatedError {
            throw simulatedError
        }
        guard storage.removeValue(forKey: id) != nil else {
            throw QuestRepositoryError.questNotFound(id)
        }
    }
}

extension InMemoryQuestRepository {
    /// Sample quests for SwiftUI Previews across macOS and iOS.
    nonisolated static var previewSampleQuests: [Quest] {
        let now = Date.now
        return [
            Quest(
                id: "quest-mug-live",
                title: "Spot the Everyday Mug",
                questDescription: "Point your camera at a coffee mug and watch VNClassifyImageRequest identify it in real time.",
                status: .published,
                publishDate: now.addingTimeInterval(-3600),
                targetLabel: "coffee_cup",
                hintText: "Check the kitchen counter or desk!",
                resources: [
                    LearningResource(
                        title: "VNClassifyImageRequest — Apple Developer Documentation",
                        urlString: "https://developer.apple.com/documentation/vision/vnclassifyimagerequest"
                    ),
                    LearningResource(
                        title: "Classifying Images for Categorization and Search",
                        urlString: "https://developer.apple.com/documentation/vision/classifying_images_for_categorization_and_search"
                    )
                ],
                updatedAt: now.addingTimeInterval(-3600)
            ),
            Quest(
                id: "quest-keyboard-scheduled",
                title: "Mechanical or Magic? Classify a Keyboard",
                questDescription: "Explore how Vision distinguishes computer keyboards from laptops and desks.",
                status: .published,
                publishDate: now.addingTimeInterval(86400),
                targetLabel: "keyboard",
                hintText: "Look right in front of your Mac!",
                resources: [
                    LearningResource(
                        title: "VNClassificationObservation Documentation",
                        urlString: "https://developer.apple.com/documentation/vision/vnclassificationobservation"
                    )
                ],
                updatedAt: now.addingTimeInterval(-1800)
            ),
            Quest(
                id: "quest-plant-draft",
                title: "Indoor Plant Identifier",
                questDescription: "Test scene and plant classification using live camera frames.",
                status: .draft,
                publishDate: now,
                targetLabel: "houseplant",
                hintText: nil,
                resources: [
                    LearningResource(
                        title: "Vision Framework Overview",
                        urlString: "https://developer.apple.com/documentation/vision"
                    )
                ],
                updatedAt: now.addingTimeInterval(-600)
            )
        ]
    }
}
