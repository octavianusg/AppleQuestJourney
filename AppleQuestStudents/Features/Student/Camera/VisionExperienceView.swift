import AVFoundation
import SwiftUI
import UIKit

/// Full-screen live camera Vision Scavenger Hunt view with the real-time **Developer HUD**, optional Mentor Hint banner, and Target Match celebration (`REQ-S04`, `REQ-S05`, `REQ-S06`, `REQ-S07`).
struct VisionExperienceView: View {
    let quest: Quest
    var onTargetMatched: (Double) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var cameraManager: LiveCameraManager

    init(
        quest: Quest,
        cameraManager: LiveCameraManager? = nil,
        onTargetMatched: @escaping (Double) -> Void = { _ in }
    ) {
        self.quest = quest
        self.onTargetMatched = onTargetMatched
        _cameraManager = State(
            initialValue: cameraManager ?? LiveCameraManager(quest: quest)
        )
    }

    var body: some View {
        ZStack {
            // 1. Live Camera Feed Layer (`REQ-S04`)
            cameraPreviewBackdrop
                .ignoresSafeArea()

            // 2. Scavenger Hunt Reticle & Target Overlay
            viewfinderReticleOverlay

            // 3. Top & Bottom HUD Controls (`REQ-S05`, `REQ-S06`, `REQ-S07`)
            VStack(spacing: 12) {
                topNavigationAndHintBar

                if cameraManager.hasHint, cameraManager.isHintRevealed, let hint = cameraManager.normalizedHint {
                    mentorHintBanner(hint: hint)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                if cameraManager.isCompleted, let match = cameraManager.matchedObservation {
                    targetMatchedCelebrationCard(match: match)
                        .transition(.scale.combined(with: .opacity))
                } else if cameraManager.authorizationState == .unavailable || !cameraManager.isSessionRunning {
                    simulatorTestControlsBar
                }

                developerHUDPanel
            }
            .padding(16)
            .animation(.spring(duration: 0.3), value: cameraManager.isHintRevealed)
            .animation(.spring(duration: 0.35), value: cameraManager.isCompleted)
        }
        .task {
            await cameraManager.startCamera()
        }
        .onDisappear {
            cameraManager.stopCamera()
        }
        .onChange(of: cameraManager.isCompleted) { _, completed in
            if completed, let match = cameraManager.matchedObservation {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                onTargetMatched(match.confidence)
            }
        }
    }

    // MARK: - Camera Preview Backdrop (`REQ-S04`)

    private var cameraPreviewBackdrop: some View {
        ZStack {
            Color.black

            CameraPreviewLayerView(session: cameraManager.captureSession)

            if !cameraManager.isSessionRunning {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.09, blue: 0.16),
                        Color(red: 0.03, green: 0.05, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 52))
                            .foregroundStyle(.cyan.opacity(0.65))

                        Text("Point Camera at \"\(quest.targetLabel)\"")
                            .font(.headline)
                            .foregroundStyle(.white)

                        if let statusMessage = cameraManager.statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Viewfinder Reticle

    private var viewfinderReticleOverlay: some View {
        RoundedRectangle(cornerRadius: 28)
            .strokeBorder(
                cameraManager.isCompleted ? Color.green : Color.cyan.opacity(0.7),
                style: StrokeStyle(lineWidth: cameraManager.isCompleted ? 3.5 : 2, dash: [18, 10])
            )
            .frame(width: 240, height: 240)
            .allowsHitTesting(false)
    }

    // MARK: - Top Navigation & Optional Hint Button (`REQ-S06`)

    private var topNavigationAndHintBar: some View {
        HStack(spacing: 12) {
            Button {
                cameraManager.stopCamera()
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }

            Spacer()

            // Optional Mentor Hint Button (`REQ-S06`: shown ONLY when hintText is non-nil)
            if cameraManager.hasHint {
                Button {
                    cameraManager.toggleHint()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: cameraManager.isHintRevealed ? "lightbulb.fill" : "lightbulb")
                            .foregroundStyle(.yellow)
                        Text(cameraManager.isHintRevealed ? "Hide Hint" : "Hint")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func mentorHintBanner(hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.max.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mentor Hint")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.yellow)
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(12)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.yellow.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Target Matched Celebration Card (`REQ-S07`)

    private func targetMatchedCelebrationCard(match: VisionObservationItem) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Classified!")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Matched `\(match.identifier)` at \(match.confidencePercentageText) confidence")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                }

                Spacer()
            }

            Text("You unlocked \(quest.resources.count) mentor learning resource\(quest.resources.count == 1 ? "" : "s") and saved this quest to your library.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    cameraManager.resetForReplay()
                } label: {
                    Label("Scan Again", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    cameraManager.stopCamera()
                    dismiss()
                } label: {
                    Label("View Unlocked Resources", systemImage: "lock.open.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(16)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.green.opacity(0.75), lineWidth: 1.5)
        )
    }

    // MARK: - Simulator / Preview Test Controls

    private var simulatorTestControlsBar: some View {
        HStack(spacing: 10) {
            Button {
                cameraManager.processObservations([
                    VisionObservationItem(identifier: quest.targetLabel, confidence: 0.54),
                    VisionObservationItem(identifier: "desk", confidence: 0.31),
                    VisionObservationItem(identifier: "indoor", confidence: 0.19)
                ])
            } label: {
                Label("Simulate Partial (54%)", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(.white)
            }

            Button {
                cameraManager.processObservations([
                    VisionObservationItem(identifier: quest.targetLabel, confidence: 0.91),
                    VisionObservationItem(identifier: "tableware", confidence: 0.62),
                    VisionObservationItem(identifier: "indoor", confidence: 0.28)
                ])
            } label: {
                Label("Simulate Match (91%)", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.green.opacity(0.28), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Real-Time Developer HUD Overlay (`REQ-S05`)

    private var developerHUDPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // HUD Header: Request Class Name & Live Status
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(cameraManager.isCompleted ? Color.green : Color.cyan)
                        .frame(width: 8, height: 8)
                    Text("DEVELOPER HUD")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.cyan)
                }

                Spacer()

                // (1) Active API Request Class (`REQ-S05`)
                Text(cameraManager.requestClassName)
                    .font(.caption2.monospaced().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.cyan)
            }

            // (2) Target Taxonomy Identifier & Required Confidence (`REQ-S05`)
            HStack {
                Text("TARGET IDENTIFIER:")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.65))

                Text(cameraManager.targetLabel)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.yellow)

                Spacer()

                Text("THRESHOLD >= \(Int((cameraManager.confidenceThreshold * 100).rounded()))%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.65))
            }

            Divider()
                .background(.white.opacity(0.2))

            // (3) Top 3 Live `VNClassificationObservation` Identifiers + Real-Time Confidence (`REQ-S05`)
            Text("TOP 3 VNClassificationObservation OUTPUTS")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

            if cameraManager.topObservations.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.cyan)
                        .scaleEffect(0.8)
                    Text("Awaiting live camera frames for VNClassifyImageRequest…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(cameraManager.topObservations.enumerated()), id: \.element.id) { index, observation in
                        let isTarget = observation.identifier.lowercased() == cameraManager.targetLabel.lowercased()
                        let meetsThreshold = isTarget && observation.confidence >= cameraManager.confidenceThreshold

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("#\(index + 1) \(observation.identifier)")
                                    .font(.caption.monospaced().weight(isTarget ? .bold : .medium))
                                    .foregroundStyle(meetsThreshold ? .green : (isTarget ? .yellow : .white))

                                if isTarget {
                                    Text(meetsThreshold ? "MATCH" : "TARGET")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(
                                            (meetsThreshold ? Color.green : Color.yellow).opacity(0.25),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(meetsThreshold ? .green : .yellow)
                                }

                                Spacer()

                                Text(observation.confidencePercentageText)
                                    .font(.caption.monospaced().weight(.bold))
                                    .foregroundStyle(meetsThreshold ? .green : .cyan)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.14))
                                    Capsule()
                                        .fill(meetsThreshold ? Color.green : (isTarget ? Color.yellow : Color.cyan))
                                        .frame(width: max(4, geo.size.width * observation.confidence))
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.cyan.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - UIKit AVCaptureVideoPreviewLayer Bridge (`REQ-S04`)

private struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

#Preview("Vision Experience — Live Developer HUD") {
    let sampleQuest = InMemoryQuestRepository.previewSampleQuests[0]
    let manager = LiveCameraManager(quest: sampleQuest)
    manager.isHintRevealed = true
    manager.processObservations([
        VisionObservationItem(identifier: "coffee_cup", confidence: 0.64),
        VisionObservationItem(identifier: "mug", confidence: 0.41),
        VisionObservationItem(identifier: "tableware", confidence: 0.22)
    ])
    return VisionExperienceView(quest: sampleQuest, cameraManager: manager)
}

#Preview("Vision Experience — Target Matched") {
    let sampleQuest = InMemoryQuestRepository.previewSampleQuests[0]
    let manager = LiveCameraManager(quest: sampleQuest)
    manager.processObservations([
        VisionObservationItem(identifier: "coffee_cup", confidence: 0.92),
        VisionObservationItem(identifier: "mug", confidence: 0.58),
        VisionObservationItem(identifier: "tableware", confidence: 0.31)
    ])
    return VisionExperienceView(quest: sampleQuest, cameraManager: manager)
}
