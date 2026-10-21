import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import Observation

/// Camera authorization and hardware readiness state for the Student Vision Scavenger Hunt (`REQ-S04`).
nonisolated enum CameraAuthorizationState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

/// Manages `AVCaptureSession`, background video sample buffer throttling, `VNClassifyImageRequest` evaluation, and Developer HUD state (`REQ-S04`, `REQ-S05`, `REQ-S06`, `REQ-S07`).
@Observable
@MainActor
final class LiveCameraManager {
    /// Active Vision request class name exposed in the Developer HUD (`REQ-S05`).
    let requestClassName: String = VisionFrameEvaluation.requestClassName

    /// Target Vision taxonomy identifier for the current quest (`REQ-S04`, `REQ-S05`, `REQ-S07`).
    let targetLabel: String

    /// Confidence threshold (`0.70`) required to complete the Vision Scavenger Hunt (`REQ-S07`).
    let confidenceThreshold: Double

    /// Normalized mentor hint (`nil` when blank or omitted) (`REQ-S06`).
    let normalizedHint: String?

    /// Whether a mentor hint control should be displayed (`REQ-S06`).
    var hasHint: Bool {
        normalizedHint != nil
    }

    /// Whether the student has toggled the hint banner open (`REQ-S06`).
    var isHintRevealed: Bool = false

    /// Current camera authorization / availability state (`REQ-S04`).
    var authorizationState: CameraAuthorizationState = .notDetermined

    /// Whether the capture session is actively running (`REQ-S04`).
    var isSessionRunning: Bool = false

    /// Top 3 live `VNClassificationObservation` items displayed in the Developer HUD (`REQ-S05`).
    var topObservations: [VisionObservationItem] = []

    /// Non-nil once an observation matches `targetLabel` with `confidence >= confidenceThreshold` (`REQ-S07`).
    var matchedObservation: VisionObservationItem?

    /// Whether the quest's target label has been matched and completed (`REQ-S07`).
    var isCompleted: Bool = false

    /// Optional status/error message if camera hardware is unavailable (e.g., on Simulator).
    var statusMessage: String?

    /// Underlying `AVCaptureSession` bound to the live camera preview layer.
    nonisolated let captureSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.applequest.students.camera.session", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "com.applequest.students.camera.videoOutput", qos: .userInitiated)
    private var sampleBufferDelegateProxy: SampleBufferDelegateProxy?
    private var isConfigured: Bool = false

    init(
        targetLabel: String,
        hintText: String? = nil,
        confidenceThreshold: Double = VisionClassifierService.defaultTargetConfidenceThreshold
    ) {
        self.targetLabel = targetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedHint = QuestValidator.normalizedHint(hintText)
        self.confidenceThreshold = confidenceThreshold
    }

    convenience init(
        quest: Quest,
        confidenceThreshold: Double = VisionClassifierService.defaultTargetConfidenceThreshold
    ) {
        self.init(
            targetLabel: quest.targetLabel,
            hintText: quest.hintText,
            confidenceThreshold: confidenceThreshold
        )
    }

    // MARK: - Deterministic Observation Processing (`REQ-S05`, `REQ-S07`)

    /// Processes a batch of `VisionObservationItem` results, updating the Developer HUD's Top 3 list (`REQ-S05`) and triggering completion if `targetLabel` meets `confidenceThreshold` (`REQ-S07`).
    /// Returns the matched observation if this call newly triggered completion.
    @discardableResult
    func processObservations(_ observations: [VisionObservationItem]) -> VisionObservationItem? {
        let evaluation = VisionClassifierService.evaluateFrameObservations(
            observations,
            targetLabel: targetLabel,
            threshold: confidenceThreshold,
            hudTopCount: 3
        )

        topObservations = evaluation.topObservations

        if !isCompleted, let match = evaluation.matchedObservation {
            matchedObservation = match
            isCompleted = true
            return match
        }

        return nil
    }

    /// Toggles the mentor hint banner visibility (`REQ-S06`).
    func toggleHint() {
        guard hasHint else { return }
        isHintRevealed.toggle()
    }

    /// Resets completion state so the student can replay the live camera experience (`REQ-S12`).
    func resetForReplay() {
        isCompleted = false
        matchedObservation = nil
        topObservations = []
    }

    // MARK: - Live Camera Lifecycle (`REQ-S04`)

    func startCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            authorizationState = .authorized
            configureAndStartSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                authorizationState = .authorized
                configureAndStartSession()
            } else {
                authorizationState = .denied
                statusMessage = "Camera access is required to run the live Vision Scavenger Hunt."
            }
        case .denied, .restricted:
            authorizationState = .denied
            statusMessage = "Camera permission was denied. Enable Camera access in Settings to classify live frames."
        @unknown default:
            authorizationState = .unavailable
        }
    }

    func stopCamera() {
        let session = captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        isSessionRunning = false
    }

    private func configureAndStartSession() {
        let target = targetLabel
        let threshold = confidenceThreshold

        let proxy = SampleBufferDelegateProxy(
            targetLabel: target,
            threshold: threshold
        ) { [weak self] observations in
            Task { @MainActor [weak self] in
                guard let self, !self.isCompleted else { return }
                self.processObservations(observations)
            }
        }
        self.sampleBufferDelegateProxy = proxy

        let session = captureSession
        let outputQueue = videoOutputQueue
        let alreadyConfigured = isConfigured

        sessionQueue.async { [weak self] in
            if !alreadyConfigured {
                session.beginConfiguration()
                session.sessionPreset = .high

                guard
                    let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video),
                    let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                    session.canAddInput(videoInput)
                else {
                    session.commitConfiguration()
                    Task { @MainActor [weak self] in
                        self?.authorizationState = .unavailable
                        self?.statusMessage = "No physical camera feed detected on this device/simulator. Use the Developer HUD Simulator Controls below to test live VNClassifyImageRequest observations."
                    }
                    return
                }

                session.addInput(videoInput)

                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(proxy, queue: outputQueue)

                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                }

                session.commitConfiguration()
            }

            if !session.isRunning {
                session.startRunning()
            }

            Task { @MainActor [weak self] in
                self?.isConfigured = true
                self?.isSessionRunning = session.isRunning
            }
        }
    }
}

// MARK: - Background Sample Buffer Delegate (`nonisolated`)

private nonisolated final class SampleBufferDelegateProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let targetLabel: String
    private let threshold: Double
    private let onObservations: @Sendable ([VisionObservationItem]) -> Void

    private var lastAnalysisTimestamp: TimeInterval = 0
    private let minimumFrameInterval: TimeInterval = 0.25 // ~4 FPS throttled analysis
    private var isAnalyzingFrame: Bool = false

    init(
        targetLabel: String,
        threshold: Double,
        onObservations: @escaping @Sendable ([VisionObservationItem]) -> Void
    ) {
        self.targetLabel = targetLabel
        self.threshold = threshold
        self.onObservations = onObservations
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard !isAnalyzingFrame, (now - lastAnalysisTimestamp) >= minimumFrameInterval else {
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        isAnalyzingFrame = true
        lastAnalysisTimestamp = now
        defer { isAnalyzingFrame = false }

        do {
            let observations = try VisionClassifierService.classifyPixelBuffer(
                pixelBuffer,
                orientation: .right,
                maxResults: 5,
                minimumConfidence: 0.01
            )
            onObservations(observations)
        } catch {
            // Ignore transient frame errors to keep live camera feed smooth
        }
    }
}
