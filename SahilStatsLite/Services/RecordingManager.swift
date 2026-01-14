//
//  RecordingManager.swift
//  SahilStatsLite
//
//  Simplified video recording manager using AVFoundation
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
    private var videoOutput: AVCaptureMovieFileOutput?
    private var currentVideoDevice: AVCaptureDevice?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Output

    private var currentRecordingURL: URL?

    // Score timeline for post-processing overlay
    var scoreTimeline: [ScoreTimelineTracker.ScoreSnapshot] = []

    // Completion handler for when recording finishes writing to disk
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
        scoreTimeline = []
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingFinishedContinuation = nil
    }

    /// Stop the capture session (call when leaving recording)
    @MainActor
    func stopSession() {
        debugPrint("📹 Stopping capture session")
        captureSession?.stopRunning()

        // Clear all session-related state for clean restart
        captureSession = nil
        videoOutput = nil
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

        // Set quality
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
                } else {
                    debugPrint("❌ Cannot add video input to session")
                }
            } catch {
                debugPrint("❌ Failed to create video input: \(error)")
                self.error = "Failed to setup camera: \(error.localizedDescription)"
                return
            }
        } else {
            debugPrint("❌ No back camera found!")
        }

        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            debugPrint("📹 Found audio device: \(audioDevice.localizedName)")
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    debugPrint("📹 Added audio input")
                } else {
                    debugPrint("⚠️ Cannot add audio input")
                }
            } catch {
                debugPrint("⚠️ Failed to setup audio: \(error.localizedDescription)")
            }
        } else {
            debugPrint("⚠️ No audio device found")
        }

        // Add movie output
        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            videoOutput = movieOutput
            debugPrint("📹 Added movie output")

            // Set video stabilization if available
            if let connection = movieOutput.connection(with: .video) {
                debugPrint("📹 Movie output has video connection")
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                    debugPrint("📹 Enabled video stabilization")
                }
            } else {
                debugPrint("❌ Movie output has NO video connection!")
            }
        } else {
            debugPrint("❌ Cannot add movie output to session!")
        }

        session.commitConfiguration()
        captureSession = session
        debugPrint("📹 Session configured, inputs: \(session.inputs.count), outputs: \(session.outputs.count)")

        // Start session on background thread and wait for it
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                let isRunning = session.isRunning
                debugPrint("📹 Capture session startRunning() called, isRunning: \(isRunning)")

                // Give the session a moment to stabilize before allowing recording
                Thread.sleep(forTimeInterval: 0.5)

                DispatchQueue.main.async {
                    self?.isSessionReady = true
                    continuation.resume()
                }
            }
        }

        debugPrint("📹 Setup complete, isSessionReady: \(isSessionReady)")
    }

    // MARK: - Recording Control

    @MainActor
    func startRecording() {
        debugPrint("📹 startRecording() called")

        // Check for simulator
        #if targetEnvironment(simulator)
        debugPrint("⚠️ Cannot record on simulator - no camera")
        return
        #endif

        // Prevent double-start
        guard !isRecording else {
            debugPrint("⚠️ Recording already in progress, ignoring start request")
            return
        }

        guard let session = captureSession else {
            debugPrint("❌ No capture session available")
            return
        }

        debugPrint("📹 Capture session running: \(session.isRunning)")

        guard let output = videoOutput else {
            debugPrint("❌ No video output available")
            return
        }

        debugPrint("📹 Video output exists, isRecording: \(output.isRecording)")

        guard !output.isRecording else {
            debugPrint("⚠️ AVFoundation already recording, ignoring start request")
            return
        }

        // Check connections
        if let connection = output.connection(with: .video) {
            debugPrint("📹 Video connection active: \(connection.isActive), enabled: \(connection.isEnabled)")
        } else {
            debugPrint("❌ No video connection on output!")
        }

        // Create output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "game_\(dateFormatter.string(from: Date())).mov"
        let outputURL = documentsPath.appendingPathComponent(fileName)

        debugPrint("📹 Output URL: \(outputURL.path)")

        // Delete if exists
        try? FileManager.default.removeItem(at: outputURL)

        currentRecordingURL = outputURL
        recordingStartTime = Date()

        // Mark as recording BEFORE starting to prevent race conditions
        isRecording = true

        // Start recording
        debugPrint("📹 Calling output.startRecording()...")
        output.startRecording(to: outputURL, recordingDelegate: self)

        // Start duration timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let startTime = self.recordingStartTime
            Task { @MainActor [weak self] in
                if let startTime = startTime {
                    self?.recordingDuration = Date().timeIntervalSince(startTime)
                }
            }
        }

        debugPrint("📹 Recording setup complete: \(outputURL.lastPathComponent)")
    }

    @MainActor
    func stopRecording() {
        guard let output = videoOutput, output.isRecording else { return }

        output.stopRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil

        isRecording = false
        isFileReady = false
        debugPrint("Recording stopped, waiting for file to finish writing...")
    }

    /// Stops recording and waits for the file to be fully written
    @MainActor
    func stopRecordingAndWait() async -> URL? {
        debugPrint("📹 stopRecordingAndWait() called")
        debugPrint("📹 videoOutput exists: \(videoOutput != nil)")
        debugPrint("📹 videoOutput.isRecording: \(videoOutput?.isRecording ?? false)")
        debugPrint("📹 currentRecordingURL: \(currentRecordingURL?.lastPathComponent ?? "nil")")

        guard let output = videoOutput, output.isRecording else {
            debugPrint("⚠️ Not actually recording, returning currentRecordingURL")
            return currentRecordingURL
        }

        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isFileReady = false

        return await withCheckedContinuation { continuation in
            self.recordingFinishedContinuation = continuation
            output.stopRecording()
            debugPrint("📹 Recording stopped, waiting for file to finish writing...")
        }
    }

    func getRecordingURL() -> URL? {
        return currentRecordingURL
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
            debugPrint("Failed to set zoom: \(error)")
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
                guard status == .authorized else {
                    continuation.resume(returning: false)
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    if let error = error {
                        debugPrint("Failed to save to photos: \(error)")
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

// MARK: - Recording Delegate

extension RecordingManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        debugPrint("Recording started to file: \(fileURL.lastPathComponent)")
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            debugPrint("❌ Recording error: \(error.localizedDescription)")
            // Log the full error for debugging
            debugPrint("❌ Full error: \(error)")
            Task { @MainActor in
                self.error = error.localizedDescription
                self.isFileReady = false
                self.isRecording = false  // Reset so user can try again
                // Stop the timer
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                // Resume continuation with nil on error
                self.recordingFinishedContinuation?.resume(returning: nil)
                self.recordingFinishedContinuation = nil
            }
        } else {
            debugPrint("✅ Recording finished and file ready: \(outputFileURL.lastPathComponent)")
            Task { @MainActor in
                self.isFileReady = true
                self.isRecording = false
                // Resume continuation with the URL
                self.recordingFinishedContinuation?.resume(returning: outputFileURL)
                self.recordingFinishedContinuation = nil
            }
        }
    }
}
