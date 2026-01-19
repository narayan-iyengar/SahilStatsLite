//
//  RecordingManager.swift
//  SahilStatsLite
//
//  Real-time video recording with burned-in scoreboard overlay
//  Uses AVCaptureVideoDataOutput + AVAssetWriter for frame-by-frame processing
//

import Foundation
@preconcurrency import AVFoundation
import UIKit
import Photos
import Combine

class RecordingManager: NSObject, ObservableObject {
    static let shared = RecordingManager()

    // MARK: - Published Properties

    @MainActor @Published var isRecording: Bool = false
    @MainActor @Published var recordingDuration: TimeInterval = 0
    @MainActor @Published var error: String?
    @MainActor @Published var isSessionReady: Bool = false
    @MainActor @Published var permissionGranted: Bool = false
    @MainActor @Published var isSimulator: Bool = false

    // MARK: - Capture Session

    @MainActor private(set) var captureSession: AVCaptureSession?
    private nonisolated(unsafe) var videoDataOutput: AVCaptureVideoDataOutput?
    private nonisolated(unsafe) var audioDataOutput: AVCaptureAudioDataOutput?
    private var currentVideoDevice: AVCaptureDevice?

    // MARK: - Asset Writer (for recording with overlay - accessed from processing queue)

    private nonisolated(unsafe) var assetWriter: AVAssetWriter?
    private nonisolated(unsafe) var videoWriterInput: AVAssetWriterInput?
    private nonisolated(unsafe) var audioWriterInput: AVAssetWriterInput?
    private nonisolated(unsafe) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // MARK: - Recording State (accessed from processing queue - not MainActor)

    private nonisolated(unsafe) var isWritingStarted = false
    private nonisolated(unsafe) var recordingStartTime: CMTime?
    private nonisolated(unsafe) var currentRecordingURL: URL?
    private nonisolated(unsafe) var isWriterConfigured = false
    private nonisolated(unsafe) var pendingOutputURL: URL?
    private var recordingTimer: Timer?
    private let processingQueue = DispatchQueue(label: "com.sahilstats.videoProcessing", qos: .userInitiated)

    // MARK: - Overlay Renderer

    let overlayRenderer = OverlayRenderer()

    // MARK: - Completion Handler

    private var recordingFinishedContinuation: CheckedContinuation<URL?, Never>?
    @MainActor @Published var isFileReady: Bool = false

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    /// Reset the recording manager state for a new game
    @MainActor
    func reset() {
        debugPrint("📹 RecordingManager reset")
        isRecording = false
        recordingDuration = 0
        error = nil
        isFileReady = false
        currentRecordingURL = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingFinishedContinuation = nil
        isWritingStarted = false
        isWriterConfigured = false
        recordingStartTime = nil
        pendingOutputURL = nil
    }

    /// Stop the capture session (call when leaving recording)
    @MainActor
    func stopSession() {
        debugPrint("📹 Stopping capture session")
        captureSession?.stopRunning()

        // Clear all session-related state for clean restart
        captureSession = nil
        videoDataOutput = nil
        audioDataOutput = nil
        currentVideoDevice = nil
        isSessionReady = false
    }

    // MARK: - Permissions

    @MainActor
    func requestPermissionsAndSetup() async {
        // Check camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraStatus {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            permissionGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            permissionGranted = false
            error = "Camera access denied. Please enable in Settings."
            return
        }

        // Also request microphone
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        if permissionGranted {
            await setupCaptureSession()
        }
    }

    // MARK: - Setup

    @MainActor
    private func setupCaptureSession() async {
        debugPrint("📹 Setting up capture session...")

        // Check if running on simulator
        #if targetEnvironment(simulator)
        debugPrint("⚠️ Running on SIMULATOR - camera not available!")
        isSimulator = true
        error = "Camera recording requires a physical device. The simulator doesn't have camera access."
        isSessionReady = true  // Set ready so UI can show message
        return
        #endif

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Set quality - prefer 1080p for real-time processing (4K is too heavy)
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
            debugPrint("📹 Using 1080p preset")
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
            debugPrint("📹 Using 720p preset")
        }

        // Add video input (back camera)
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            currentVideoDevice = videoDevice
            debugPrint("📹 Found back camera: \(videoDevice.localizedName)")

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                    debugPrint("📹 Added video input")
                }
            } catch {
                debugPrint("❌ Failed to create video input: \(error)")
                self.error = "Failed to setup camera: \(error.localizedDescription)"
                return
            }
        }

        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    debugPrint("📹 Added audio input")
                }
            } catch {
                debugPrint("⚠️ Failed to setup audio: \(error.localizedDescription)")
            }
        }

        // Add video data output (for frame-by-frame processing)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoDataOutput = videoOutput
            debugPrint("📹 Added video data output")
            // Video rotation is configured when recording starts based on device orientation
        }

        // Add audio data output
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: processingQueue)

        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            audioDataOutput = audioOutput
            debugPrint("📹 Added audio data output")
        }

        session.commitConfiguration()
        captureSession = session

        // Start session on background thread
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                debugPrint("📹 Capture session started, isRunning: \(session.isRunning)")

                Thread.sleep(forTimeInterval: 0.3)

                DispatchQueue.main.async {
                    self?.isSessionReady = true
                    continuation.resume()
                }
            }
        }
    }

    /// Configure video rotation based on current device orientation
    /// Call this when recording starts to capture the correct orientation
    private func configureVideoRotationForRecording() {
        guard let videoOutput = videoDataOutput,
              let connection = videoOutput.connection(with: .video) else {
            debugPrint("⚠️ No video connection to configure rotation")
            return
        }

        let deviceOrientation = UIDevice.current.orientation
        let rotationAngle: CGFloat

        // Determine rotation based on how device is held
        // Swapped values to fix upside-down video
        switch deviceOrientation {
        case .landscapeLeft:
            // Device held with volume buttons down, home button on left
            rotationAngle = 0
        case .landscapeRight:
            // Device held with volume buttons up, home button on right
            rotationAngle = 180
        default:
            // Use interface orientation as fallback for landscape detection
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let interfaceOrientation = windowScene.effectiveGeometry.interfaceOrientation
                switch interfaceOrientation {
                case .landscapeLeft:
                    rotationAngle = 180
                case .landscapeRight:
                    rotationAngle = 0
                default:
                    rotationAngle = 180  // Default
                }
            } else {
                rotationAngle = 180
            }
        }

        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
            debugPrint("📹 Set video rotation to \(rotationAngle)° for device orientation: \(deviceOrientation.rawValue)")
        } else {
            debugPrint("⚠️ Rotation angle \(rotationAngle)° not supported")
        }
    }

    // MARK: - Recording Control

    @MainActor
    func startRecording() {
        debugPrint("📹 startRecording() called")

        #if targetEnvironment(simulator)
        debugPrint("⚠️ Cannot record on simulator")
        return
        #endif

        guard !isRecording else {
            debugPrint("⚠️ Already recording")
            return
        }

        // Create output URL - but don't setup writer yet (wait for first frame to get dimensions)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "game_\(dateFormatter.string(from: Date())).mov"
        let outputURL = documentsPath.appendingPathComponent(fileName)

        // Delete if exists
        try? FileManager.default.removeItem(at: outputURL)

        // Store URL for lazy writer setup
        pendingOutputURL = outputURL
        currentRecordingURL = outputURL
        isWriterConfigured = false

        // Configure video rotation based on current device orientation
        configureVideoRotationForRecording()

        isRecording = true
        isWritingStarted = false
        recordingStartTime = nil

        // Start duration timer
        let startTime = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }

        debugPrint("📹 Recording started (waiting for first frame): \(outputURL.lastPathComponent)")
    }

    /// Setup asset writer with actual frame dimensions (called lazily on first frame)
    private func setupAssetWriter(outputURL: URL, width: Int, height: Int) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        debugPrint("📹 Setting up asset writer with dimensions: \(width)x\(height)")

        // Video settings - match actual frame dimensions
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,  // 10 Mbps
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        // No transform needed - frames come in landscape orientation via videoRotationAngle = 0
        // The overlay is drawn at the bottom of the landscape frame

        // Pixel buffer adaptor for efficient writing
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }

        // Audio settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }

        assetWriter = writer
        videoWriterInput = videoInput
        audioWriterInput = audioInput
        pixelBufferAdaptor = adaptor

        debugPrint("📹 Asset writer configured for \(width)x\(height)")
    }

    @MainActor
    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil

        finishWriting()
    }

    @MainActor
    func stopRecordingAndWait() async -> URL? {
        guard isRecording else {
            return currentRecordingURL
        }

        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil

        return await withCheckedContinuation { continuation in
            self.recordingFinishedContinuation = continuation
            finishWriting()
        }
    }

    private func finishWriting() {
        processingQueue.async { [weak self] in
            guard let self = self, let writer = self.assetWriter else {
                self?.resumeFinishedContinuation(with: nil)
                return
            }

            self.videoWriterInput?.markAsFinished()
            self.audioWriterInput?.markAsFinished()

            writer.finishWriting {
                let url = self.currentRecordingURL
                debugPrint("📹 Recording finished: \(url?.lastPathComponent ?? "nil")")

                Task { @MainActor in
                    self.isFileReady = true
                }

                self.resumeFinishedContinuation(with: url)

                // Cleanup
                self.assetWriter = nil
                self.videoWriterInput = nil
                self.audioWriterInput = nil
                self.pixelBufferAdaptor = nil
                self.isWriterConfigured = false
                self.pendingOutputURL = nil
            }
        }
    }

    private func resumeFinishedContinuation(with url: URL?) {
        DispatchQueue.main.async { [weak self] in
            self?.recordingFinishedContinuation?.resume(returning: url)
            self?.recordingFinishedContinuation = nil
        }
    }

    func getRecordingURL() -> URL? {
        return currentRecordingURL
    }

    // MARK: - Overlay State Updates

    func updateOverlay(homeTeam: String, awayTeam: String, homeScore: Int, awayScore: Int, period: String, clockTime: String, eventName: String = "") {
        overlayRenderer.homeTeam = homeTeam
        overlayRenderer.awayTeam = awayTeam
        overlayRenderer.homeScore = homeScore
        overlayRenderer.awayScore = awayScore
        overlayRenderer.period = period
        overlayRenderer.clockTime = clockTime
        overlayRenderer.eventName = eventName
    }

    // MARK: - Camera Control

    func setZoom(factor: CGFloat) -> CGFloat {
        guard let device = currentVideoDevice else { return 1.0 }

        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 6.0)
            let clampedFactor = max(1.0, min(factor, maxZoom))
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()
            return clampedFactor
        } catch {
            return device.videoZoomFactor
        }
    }

    func getCurrentZoom() -> CGFloat {
        return currentVideoDevice?.videoZoomFactor ?? 1.0
    }

    // MARK: - Save to Photos

    func saveToPhotoLibrary() async -> Bool {
        guard let url = currentRecordingURL else { return false }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    continuation.resume(returning: false)
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    if let error = error {
                        debugPrint("❌ Failed to save to photos: \(error)")
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

// MARK: - Sample Buffer Delegate

extension RecordingManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only process if we're supposed to be recording
        guard pendingOutputURL != nil || assetWriter != nil else { return }

        // Get presentation timestamp
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Handle video frames
        if output === videoDataOutput {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // Lazily setup asset writer on first video frame to get actual dimensions
            if !isWriterConfigured {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)

                guard let outputURL = pendingOutputURL else { return }

                // Log frame info for debugging
                let isLandscape = width > height
                debugPrint("📹 First frame received: \(width)x\(height) (landscape: \(isLandscape))")

                do {
                    try setupAssetWriter(outputURL: outputURL, width: width, height: height)
                    isWriterConfigured = true
                    debugPrint("📹 Asset writer configured: \(width)x\(height)")
                } catch {
                    debugPrint("❌ Failed to setup asset writer: \(error)")
                    return
                }
            }

            guard let writer = assetWriter else { return }

            // Start writing session on first frame
            if !isWritingStarted {
                if writer.status == .unknown {
                    writer.startWriting()
                    writer.startSession(atSourceTime: timestamp)
                    recordingStartTime = timestamp
                    isWritingStarted = true
                    debugPrint("📹 Asset writer started at \(timestamp.seconds)s")
                }
            }

            guard writer.status == .writing else { return }

            processVideoFrame(pixelBuffer, timestamp: timestamp)
        }

        // Handle audio frames
        if output === audioDataOutput {
            guard let writer = assetWriter, writer.status == .writing else { return }
            processAudioFrame(sampleBuffer)
        }
    }

    nonisolated private func processVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let videoInput = videoWriterInput, videoInput.isReadyForMoreMediaData else { return }

        // Apply overlay to the frame
        _ = overlayRenderer.render(onto: pixelBuffer)

        // Write the composited frame
        pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timestamp)
    }

    nonisolated private func processAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }
}
