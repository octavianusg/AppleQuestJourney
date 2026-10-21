import SwiftUI

/// Student App feed displaying all currently published quests (`status == .published && publishDate <= Date.now`) (`REQ-S02`, `REQ-S03`, `REQ-S12`).
struct ActiveQuestsView: View {
    @Bindable var viewModel: ActiveQuestsViewModel
    var onQuestCompleted: ((Quest, Double) -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            viewModel.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                Group {
                    if viewModel.isLoading && viewModel.activeQuests.isEmpty {
                    ProgressView("Loading Active Quests…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.activeQuests.isEmpty {
                    ContentUnavailableView {
                        Label("No Active Quests Yet", systemImage: "sparkles.rectangle.stack")
                    } description: {
                        Text("When your mentor publishes a Vision Scavenger Hunt quest, it will appear here.")
                    } actions: {
                        Button {
                            Task {
                                await viewModel.loadActiveQuests()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(viewModel.activeQuests) { quest in
                                let completed = viewModel.isCompleted(quest)
                                NavigationLink {
                                    QuestDetailView(
                                        quest: quest,
                                        isCompleted: completed,
                                        achievedConfidence: viewModel.achievedConfidenceByQuestID[quest.id],
                                        onSimulateCompletion: { confidence in
                                            viewModel.markQuestCompleted(quest, confidence: confidence)
                                            onQuestCompleted?(quest, confidence)
                                        }
                                    )
                                } label: {
                                    StudentQuestCardView(
                                        quest: quest,
                                        isCompleted: completed
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                    .refreshable {
                        await viewModel.loadActiveQuests()
                    }
                    }
                }
            }
            .navigationTitle("Active Quests")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadActiveQuests()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                if viewModel.activeQuests.isEmpty {
                    await viewModel.loadActiveQuests()
                }
            }
        }
    }
}

/// Card representing an active published Quest in the Student iOS feed (`REQ-S02`, `REQ-S12`).
struct StudentQuestCardView: View {
    let quest: Quest
    let isCompleted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text("VNClassifyImageRequest")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.blue)
                }

                Spacer()

                if isCompleted {
                    Label("Completed", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(.green)
                } else {
                    Label("Locked URLs", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.14), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            if !quest.questDescription.isEmpty {
                Text(quest.questDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 10) {
                Label(quest.targetLabel, systemImage: "viewfinder")
                    .font(.caption.monospaced().weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.blue)

                Label(
                    "\(quest.resources.count) Resource\(quest.resources.count == 1 ? "" : "s")",
                    systemImage: isCompleted ? "lock.open.fill" : "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Active Quests Feed") {
    let sampleQuests = InMemoryQuestRepository.previewSampleQuests
    let repo = InMemoryQuestRepository(initialQuests: sampleQuests)
    let vm = ActiveQuestsViewModel(
        repository: repo,
        completedQuestIDs: ["quest-mug-live"]
    )
    vm.activeQuests = sampleQuests.filter { QuestCKRecordMapper.isVisibleToStudent($0, at: .now) }
    return ActiveQuestsView(viewModel: vm)
}
