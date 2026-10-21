import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit

/// Full-featured macOS Mentor Quest Editor with searchable Vision taxonomy picker (`REQ-M06`), sample photo drag-and-drop auto-suggestion (`REQ-M07`), optional hint authoring (`REQ-M08`), and dynamic learning resource validation (`REQ-M05`).
struct QuestEditorView: View {
    @State private var draftQuest: Quest
    @State private var taxonomySearchText: String = ""
    @State private var isTaxonomyPickerExpanded: Bool = false
    @State private var suggestedObservations: [VisionObservationItem] = []
    @State private var droppedPreviewImage: NSImage?
    @State private var isAnalyzingPhoto: Bool = false
    @State private var photoAnalysisErrorMessage: String?
    @State private var isDropTargeted: Bool = false
    @State private var isFileImporterPresented: Bool = false

    let isExistingQuest: Bool
    let isSaving: Bool
    let onSaveAsDraft: (Quest) -> Void
    let onPublish: (Quest, Date) -> Void
    let onDelete: () -> Void

    init(
        quest: Quest,
        isExistingQuest: Bool,
        isSaving: Bool = false,
        initialSuggestions: [VisionObservationItem] = [],
        onSaveAsDraft: @escaping (Quest) -> Void = { _ in },
        onPublish: @escaping (Quest, Date) -> Void = { _, _ in },
        onDelete: @escaping () -> Void = {}
    ) {
        _draftQuest = State(initialValue: quest)
        _suggestedObservations = State(initialValue: initialSuggestions)
        self.isExistingQuest = isExistingQuest
        self.isSaving = isSaving
        self.onSaveAsDraft = onSaveAsDraft
        self.onPublish = onPublish
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    questMetadataSection
                    visionConfigurationSection
                    learningResourcesSection
                }
                .padding(24)
            }

            Divider()
            actionBar
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFileResult(result)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(draftQuest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Vision Quest" : draftQuest.title)
                        .font(.title2.bold())
                    MentorStatusBadge(state: draftQuest.displayState())
                }
                HStack(spacing: 8) {
                    Label("VNClassifyImageRequest", systemImage: "camera.viewfinder")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.indigo.opacity(0.14), in: Capsule())
                        .foregroundStyle(.indigo)

                    Text("Vision Scavenger Hunt Experience")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isExistingQuest {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Quest", systemImage: "trash")
                }
                .disabled(isSaving)
            }
        }
    }

    // MARK: - Metadata & Schedule Section

    private var questMetadataSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Quest Title")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if draftQuest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label("Required", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    TextField(
                        "Quest Title",
                        text: $draftQuest.title,
                        prompt: Text("e.g., Spot the Everyday Mug")
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Learning Overview & Description")
                        .font(.subheadline.weight(.medium))
                    TextField(
                        "Description",
                        text: $draftQuest.questDescription,
                        prompt: Text("Explain what the student will discover about VNClassifyImageRequest…"),
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                HStack(spacing: 16) {
                    DatePicker(
                        "Publish / Schedule Date:",
                        selection: $draftQuest.publishDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Spacer()

                    Button("Set to Now") {
                        draftQuest.publishDate = .now
                    }
                    .controlSize(.small)
                }

                Text(scheduleHelperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        } label: {
            Label("1. Quest Details & Schedule", systemImage: "calendar.badge.clock")
                .font(.headline)
        }
    }

    // MARK: - Vision Target Label & Photo Auto-Suggestion Section (`REQ-M06`, `REQ-M07`, `REQ-M08`)

    private var visionConfigurationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Selected Target Label Status
                HStack(spacing: 10) {
                    Text("Selected Target Label:")
                        .font(.subheadline.weight(.medium))

                    if isTargetLabelValid {
                        Label(draftQuest.targetLabel, systemImage: "checkmark.seal.fill")
                            .font(.body.monospaced().weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.blue)
                    } else {
                        Label(
                            draftQuest.targetLabel.isEmpty ? "None Selected" : draftQuest.targetLabel,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.body.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.orange)
                    }

                    Spacer()

                    Button {
                        withAnimation(.snappy) {
                            isTaxonomyPickerExpanded.toggle()
                        }
                    } label: {
                        Label(
                            isTaxonomyPickerExpanded ? "Hide Taxonomy Browser" : "Browse All (\(VisionClassifierService.supportedTaxonomyLabels().count))",
                            systemImage: isTaxonomyPickerExpanded ? "chevron.up" : "magnifyingglass"
                        )
                    }
                    .controlSize(.small)
                }

                // Sample Photo Drop Zone (`REQ-M07`)
                photoDropZoneView

                // Suggested Taxonomy Chips (`REQ-M07`)
                if !suggestedObservations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Suggested Taxonomy Labels from Photo (Click to Select)", systemImage: "wand.and.stars")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear Suggestions") {
                                suggestedObservations = []
                                droppedPreviewImage = nil
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedObservations) { item in
                                    let isChosen = draftQuest.targetLabel == item.identifier
                                    Button {
                                        draftQuest.targetLabel = item.identifier
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: isChosen ? "checkmark.circle.fill" : "tag.fill")
                                                .font(.caption)
                                            Text(item.identifier)
                                                .font(.caption.monospaced().weight(.semibold))
                                            Text(item.confidencePercentageText)
                                                .font(.caption2.monospacedDigit())
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(.primary.opacity(0.12), in: Capsule())
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            isChosen ? Color.blue.opacity(0.22) : Color.secondary.opacity(0.12),
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isChosen ? Color.blue : Color.clear, lineWidth: 1.5)
                                        )
                                        .foregroundStyle(isChosen ? Color.blue : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Searchable Vision Taxonomy Picker (`REQ-M06`)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            "Search built-in VNClassifyImageRequest taxonomy identifiers (e.g., coffee_cup, keyboard, houseplant)…",
                            text: $taxonomySearchText
                        )
                        .textFieldStyle(.plain)
                        .onChange(of: taxonomySearchText) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                isTaxonomyPickerExpanded = true
                            }
                        }

                        if !taxonomySearchText.isEmpty {
                            Button {
                                taxonomySearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                    if isTaxonomyPickerExpanded || !taxonomySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let matchingLabels = Array(VisionClassifierService.searchTaxonomyLabels(query: taxonomySearchText).prefix(40))

                        if matchingLabels.isEmpty {
                            Text("No built-in Vision taxonomy identifiers match \"\(taxonomySearchText)\".")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.vertical, 4)
                        } else {
                            ScrollView {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 8)],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(matchingLabels, id: \.self) { label in
                                        let isSelected = draftQuest.targetLabel == label
                                        Button {
                                            draftQuest.targetLabel = label
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .font(.caption)
                                                Text(label)
                                                    .font(.caption.monospaced())
                                                    .lineLimit(1)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(
                                                isSelected ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 6)
                                            )
                                            .foregroundStyle(isSelected ? Color.blue : Color.primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(4)
                            }
                            .frame(maxHeight: 165)
                        }
                    }
                }

                Divider()

                // Optional Mentor Hint (`REQ-M08`)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Optional Student Hint")
                            .font(.subheadline.weight(.medium))
                        Text("(Shown in the iOS live camera view if provided)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField(
                        "Optional Hint",
                        text: Binding(
                            get: { draftQuest.hintText ?? "" },
                            set: { draftQuest.hintText = QuestValidator.normalizedHint($0) }
                        ),
                        prompt: Text("e.g., Check the kitchen counter or desk! (Leave blank for no hint)")
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(10)
        } label: {
            Label("2. Vision Scavenger Hunt Configuration", systemImage: "eye.square")
                .font(.headline)
        }
    }

    // MARK: - Sample Photo Drop Zone (`REQ-M07`)

    private var photoDropZoneView: some View {
        HStack(spacing: 14) {
            if let droppedPreviewImage {
                Image(nsImage: droppedPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.10))
                        .frame(width: 68, height: 68)
                    Image(systemName: "photo.badge.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Drop a Sample Photo to Auto-Detect Vision Labels")
                    .font(.subheadline.weight(.semibold))
                Text("Runs VNClassifyImageRequest on macOS and suggests matching taxonomy identifiers with confidence scores.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let photoAnalysisErrorMessage {
                    Text(photoAnalysisErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if isAnalyzingPhoto {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Choose Photo…", systemImage: "folder")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTargeted ? Color.blue.opacity(0.14) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? Color.blue : Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .dropDestination(for: Data.self) { items, _ in
            guard let firstData = items.first else { return false }
            analyzeSamplePhotoData(firstData)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    // MARK: - Learning Resources Editor (`REQ-M05`)

    private var learningResourcesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Attach external URLs (Apple Developer Documentation, WWDC videos, articles) that unlock after students complete the Vision challenge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        draftQuest.resources.append(
                            LearningResource(title: "", urlString: "https://developer.apple.com/documentation/vision")
                        )
                    } label: {
                        Label("Add Resource URL", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.small)
                }

                if draftQuest.resources.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("At least one valid http/https learning resource URL is required.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach($draftQuest.resources) { $resource in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: resource.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(resource.isValid ? .green : .orange)
                                .padding(.top, 6)
                                .help(resource.isValid ? "Valid learning resource" : "Requires a non-empty title and a valid http/https URL")

                            VStack(alignment: .leading, spacing: 6) {
                                TextField(
                                    "Resource Title",
                                    text: $resource.title,
                                    prompt: Text("Resource Title (e.g., VNClassifyImageRequest Documentation)")
                                )
                                .textFieldStyle(.roundedBorder)

                                HStack(spacing: 8) {
                                    TextField(
                                        "https://...",
                                        text: $resource.urlString,
                                        prompt: Text("https://developer.apple.com/documentation/...")
                                    )
                                    .font(.caption.monospaced())
                                    .textFieldStyle(.roundedBorder)

                                    if resource.validURL == nil {
                                        Text("Invalid http/https URL")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            Button(role: .destructive) {
                                draftQuest.resources.removeAll { $0.id == resource.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 5)
                            .disabled(draftQuest.resources.count <= 1)
                            .help(draftQuest.resources.count <= 1 ? "At least one resource is required" : "Remove resource")
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(10)
        } label: {
            Label("3. Unlocked Learning Resource URLs (\(draftQuest.resources.count))", systemImage: "link.badge.plus")
                .font(.headline)
        }
    }

    // MARK: - Bottom Action Bar (`REQ-M01`, `REQ-M02`, `REQ-M05`)

    private var actionBar: some View {
        HStack(spacing: 12) {
            if let firstValidationIssue = validationErrors.first {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(firstValidationIssue.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Quest configuration is valid and ready to save or publish.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onSaveAsDraft(draftQuest.normalized())
            } label: {
                Label("Save as Draft", systemImage: "tray.and.arrow.down")
            }
            .disabled(isSaving || !isQuestValid)

            Button {
                let normalized = draftQuest.normalized()
                onPublish(normalized, normalized.publishDate)
            } label: {
                Label(
                    draftQuest.publishDate > .now ? "Schedule Quest" : "Publish Quest",
                    systemImage: draftQuest.publishDate > .now ? "calendar.badge.clock" : "paperplane.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || !isQuestValid)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: - Validation & Photo Classification Helpers

    private var validationErrors: [QuestValidationError] {
        QuestValidator.validate(
            draftQuest,
            allowedTaxonomyLabels: VisionClassifierService.supportedTaxonomyLabelSet
        )
    }

    private var isQuestValid: Bool {
        validationErrors.isEmpty
    }

    private var isTargetLabelValid: Bool {
        let trimmed = draftQuest.targetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && VisionClassifierService.supportedTaxonomyLabelSet.contains(trimmed)
    }

    private var scheduleHelperText: String {
        if draftQuest.publishDate > .now {
            return "Students will not see this quest until \(draftQuest.publishDate.formatted(date: .abbreviated, time: .shortened)) once published."
        } else {
            return "Publishing with a current or past date makes the quest immediately visible in the iOS Student App."
        }
    }

    private func handleImportedFileResult(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                analyzeSamplePhotoData(data)
            } catch {
                photoAnalysisErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            photoAnalysisErrorMessage = error.localizedDescription
        }
    }

    private func analyzeSamplePhotoData(_ data: Data) {
        isAnalyzingPhoto = true
        photoAnalysisErrorMessage = nil
        droppedPreviewImage = NSImage(data: data)

        Task {
            do {
                let results = try await VisionClassifierService.classifyImageData(
                    data,
                    maxResults: 8,
                    minimumConfidence: 0.01
                )
                await MainActor.run {
                    suggestedObservations = results
                    if let topMatch = results.first {
                        draftQuest.targetLabel = topMatch.identifier
                    }
                    isAnalyzingPhoto = false
                }
            } catch {
                await MainActor.run {
                    photoAnalysisErrorMessage = error.localizedDescription
                    isAnalyzingPhoto = false
                }
            }
        }
    }
}

#Preview("Quest Editor — Valid & Suggested Chips") {
    let sampleQuest = InMemoryQuestRepository.previewSampleQuests[0]
    let sampleSuggestions = [
        VisionObservationItem(identifier: "coffee_cup", confidence: 0.94),
        VisionObservationItem(identifier: "espresso", confidence: 0.78),
        VisionObservationItem(identifier: "cup", confidence: 0.65),
        VisionObservationItem(identifier: "tableware", confidence: 0.51)
    ]
    return QuestEditorView(
        quest: sampleQuest,
        isExistingQuest: true,
        initialSuggestions: sampleSuggestions
    )
    .frame(width: 720, height: 740)
}
#endif
