import SwiftUI

/// Detail screen for a selected Quest showing its overview, target Vision framework badge, "Start/Replay Vision Experience" CTA, and locked/unlocked Learning Resources (`REQ-S03`, `REQ-S08`, `REQ-S12`).
struct QuestDetailView: View {
    let quest: Quest
    let isCompleted: Bool
    var achievedConfidence: Double? = nil
    var onStartExperience: () -> Void = {}
    var onSimulateCompletion: ((Double) -> Void)? = nil

    @State private var isPresentingExperienceSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                visionFrameworkInfoCard
                experienceCTAButton
                learningResourcesSection
            }
            .padding(16)
        }
        .navigationTitle(quest.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingExperienceSheet) {
            experiencePlaceholderSheet
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(quest.title)
                        .font(.title2.bold())

                    HStack(spacing: 8) {
                        Label("Vision Framework", systemImage: "eye.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.indigo.opacity(0.14), in: Capsule())
                            .foregroundStyle(.indigo)

                        if isCompleted {
                            Label(
                                achievedConfidenceText,
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(.green)
                        }
                    }
                }
                Spacer()
            }

            if !quest.questDescription.isEmpty {
                Text(quest.questDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Vision API & Target Label Card

    private var visionFrameworkInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Interactive API Challenge", systemImage: "camera.viewfinder")
                    .font(.headline)
                Spacer()
                Text("VNClassifyImageRequest")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.blue)
            }

            Divider()

            HStack {
                Text("Target Taxonomy Identifier")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(quest.targetLabel)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Text("Required Confidence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(">= 70%")
                    .font(.subheadline.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let hint = QuestValidator.normalizedHint(quest.hintText) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Mentor Hint available inside the live camera HUD (\(hint))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Start / Replay CTA (`REQ-S04`, `REQ-S12`)

    private var experienceCTAButton: some View {
        Button {
            onStartExperience()
            isPresentingExperienceSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCompleted ? "arrow.counterclockwise.circle.fill" : "camera.viewfinder")
                    .font(.title3)
                Text(isCompleted ? "Replay Vision Experience" : "Start Vision Experience")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(isCompleted ? .indigo : .blue)
    }

    // MARK: - Learning Resources Section (`REQ-S03`, `REQ-S08`, `REQ-S12`)

    private var learningResourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Curated Learning Resources (\(quest.resources.count))",
                    systemImage: isCompleted ? "lock.open.fill" : "lock.fill"
                )
                .font(.headline)
                .foregroundStyle(isCompleted ? .primary : .secondary)

                Spacer()

                Text(isCompleted ? "Unlocked" : "Locked")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (isCompleted ? Color.green : Color.orange).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(isCompleted ? .green : .orange)
            }

            if isCompleted {
                VStack(spacing: 10) {
                    ForEach(quest.resources) { resource in
                        if let url = resource.validURL {
                            Link(destination: url) {
                                HStack(spacing: 12) {
                                    Image(systemName: "safari.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(resource.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(resource.urlString)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)

                    Text("Complete the Vision Scavenger Hunt to Unlock")
                        .font(.subheadline.weight(.semibold))

                    Text("Point your camera at \"\(quest.targetLabel)\" and inspect the live VNClassifyImageRequest Developer HUD to unlock \(quest.resources.count) mentor-curated learning resource\(quest.resources.count == 1 ? "" : "s").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.orange.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Experience Sheet Hook (Wired to Live VisionExperienceView in Task 4.2)

    private var experiencePlaceholderSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Vision Scavenger Hunt")
                    .font(.title2.bold())

                Text("Target Identifier: \(quest.targetLabel)")
                    .font(.subheadline.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.12), in: Capsule())

                if let onSimulateCompletion {
                    Button {
                        onSimulateCompletion(0.92)
                        isPresentingExperienceSheet = false
                    } label: {
                        Label("Complete Target Match (92%)", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)
                }
            }
            .padding(24)
            .navigationTitle("VNClassifyImageRequest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresentingExperienceSheet = false
                    }
                }
            }
        }
    }

    private var achievedConfidenceText: String {
        if let achievedConfidence {
            return "Completed (\(Int((achievedConfidence * 100).rounded()))%)"
        }
        return "Completed"
    }
}

#Preview("Quest Detail — Locked Resources") {
    NavigationStack {
        QuestDetailView(
            quest: InMemoryQuestRepository.previewSampleQuests[0],
            isCompleted: false
        )
    }
}

#Preview("Quest Detail — Unlocked Resources") {
    NavigationStack {
        QuestDetailView(
            quest: InMemoryQuestRepository.previewSampleQuests[0],
            isCompleted: true,
            achievedConfidence: 0.91
        )
    }
}
