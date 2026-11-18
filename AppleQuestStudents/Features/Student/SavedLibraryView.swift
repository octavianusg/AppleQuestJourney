import SwiftData
import SwiftUI

/// Displays the student's permanent, offline-capable local library of completed quests and unlocked `LearningResource` URLs (`REQ-S08`, `REQ-S09`, `REQ-S10`, `REQ-S11`, `REQ-S12`).
struct SavedLibraryView: View {
    @Query(sort: \SavedQuest.completedAt, order: .reverse)
    private var savedQuests: [SavedQuest]

    var onBrowseActiveQuests: () -> Void = {}
    var onReplayCompleted: ((SavedQuest, Double) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if savedQuests.isEmpty {
                    ContentUnavailableView {
                        Label("Your Saved Library is Empty", systemImage: "books.vertical")
                    } description: {
                        Text("Complete a Vision Scavenger Hunt in Active Quests to unlock and permanently save mentor learning resources here.")
                    } actions: {
                        Button {
                            onBrowseActiveQuests()
                        } label: {
                            Label("Browse Active Quests", systemImage: "viewfinder.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(savedQuests) { savedQuest in
                                SavedQuestLibraryCard(
                                    savedQuest: savedQuest,
                                    onReplayCompleted: onReplayCompleted
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Saved Library")
        }
    }
}

/// Card inside the Saved Library displaying a completed `SavedQuest` snapshot, its unlocked external URLs (`REQ-S08`), and a direct "Replay Vision Experience" action (`REQ-S12`).
struct SavedQuestLibraryCard: View {
    let savedQuest: SavedQuest
    var onReplayCompleted: ((SavedQuest, Double) -> Void)? = nil

    @State private var isPresentingReplayExperience: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Title, Confidence Badge, and Detail NavigationLink
            NavigationLink {
                QuestDetailView(
                    quest: savedQuest.asQuestSnapshot,
                    isCompleted: true,
                    achievedConfidence: savedQuest.detectedConfidence,
                    onSimulateCompletion: { newConfidence in
                        onReplayCompleted?(savedQuest, newConfidence)
                    }
                )
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(savedQuest.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 8) {
                            Label(savedQuest.targetLabel, systemImage: "viewfinder")
                                .font(.caption.monospaced().weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(.blue)

                            Text("Completed \(savedQuest.completedAt, style: .date)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Label(savedQuest.confidencePercentageText, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)

            if !savedQuest.questDescription.isEmpty {
                Text(savedQuest.questDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            // Unlocked Learning Resources (`REQ-S08`, `REQ-S10`, `REQ-S11`)
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Unlocked Learning Resources (\(savedQuest.resources.count))",
                    systemImage: "lock.open.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

                ForEach(savedQuest.resources) { resource in
                    if let url = resource.validURL {
                        Link(destination: url) {
                            HStack(spacing: 10) {
                                Image(systemName: "safari.fill")
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(resource.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(resource.urlString)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            // Replay Completed Vision Experience CTA (`REQ-S12`)
            Button {
                isPresentingReplayExperience = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                    Text("Replay Vision Experience")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.indigo)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .fullScreenCover(isPresented: $isPresentingReplayExperience) {
            VisionExperienceView(
                quest: savedQuest.asQuestSnapshot,
                onTargetMatched: { newConfidence in
                    onReplayCompleted?(savedQuest, newConfidence)
                }
            )
        }
    }
}

#Preview("Saved Library — Populated") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SavedQuest.self, configurations: config)
    let sampleQuest = InMemoryQuestRepository.previewSampleQuests[0]
    let saved = SavedQuest(from: sampleQuest, detectedConfidence: 0.94)
    container.mainContext.insert(saved)

    return SavedLibraryView()
        .modelContainer(container)
}
