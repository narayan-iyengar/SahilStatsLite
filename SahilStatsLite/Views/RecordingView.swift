//
//  RecordingView.swift
//  SahilStatsLite
//
//  Full-screen recording view with floating controls
//  Inspired by Ubiquiti's clean floating UI
//

import SwiftUI
import AVFoundation
import UIKit

struct RecordingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var gimbalManager = GimbalTrackingManager.shared
    @ObservedObject private var timelineTracker = ScoreTimelineTracker.shared

    // Game state
    @State private var myScore: Int = 0
    @State private var opponentScore: Int = 0
    @State private var currentQuarter: Int = 1
    @State private var clockSeconds: Int = 0
    @State private var isClockRunning: Bool = false
    @State private var clockTimer: Timer?

    // UI state
    @State private var showEndConfirmation: Bool = false
    @State private var isControlsExpanded: Bool = true
    @State private var isFinishingRecording: Bool = false

    private var quarterLength: Int {
        appState.currentGame?.quarterLength ?? 6
    }

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            if recordingManager.isSimulator {
                // Simulator - no camera available
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            Text("Simulator Mode")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Camera recording requires a physical device.\nConnect your iPhone and run there.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 40)
                        }
                    )
            } else if recordingManager.isSessionReady, let session = recordingManager.captureSession {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Starting camera...")
                                .foregroundColor(.white)
                            if let error = recordingManager.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 40)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    )
            }

            // Scoreboard overlay (burns into video)
            VStack {
                scoreboardOverlay
                    .padding(.top, 60)

                Spacer()
            }

            // Floating controls (not in video)
            VStack {
                Spacer()
                floatingControlBar
                    .padding(.bottom, 30)
            }

            // Quarter change overlay
            if showEndConfirmation {
                endGameConfirmation
            }
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .task {
            // Reset state from any previous recording
            recordingManager.reset()

            await recordingManager.requestPermissionsAndSetup()

            // Session is now ready, start recording (unless on simulator)
            if recordingManager.isSessionReady && !recordingManager.isSimulator {
                startRecording()
            }
        }
        .onDisappear {
            stopRecording()
            recordingManager.stopSession()
        }
    }

    // MARK: - Scoreboard Overlay (Burns into video)

    private var scoreboardOverlay: some View {
        HStack(spacing: 0) {
            // My team
            HStack(spacing: 8) {
                Text(appState.currentGame?.teamName ?? "HOME")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text("\(myScore)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
            }
            .frame(maxWidth: .infinity)

            // Divider + Clock
            VStack(spacing: 2) {
                Text("Q\(currentQuarter)")
                    .font(.system(size: 12, weight: .medium))

                Text(clockString)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            .frame(width: 60)

            // Opponent
            HStack(spacing: 8) {
                Text("\(opponentScore)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))

                Text(appState.currentGame?.opponent ?? "AWAY")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
        .padding(.horizontal, 40)
    }

    // MARK: - Floating Control Bar (Ubiquiti-style)

    private var floatingControlBar: some View {
        HStack(spacing: 16) {
            // Record indicator
            recordIndicator

            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.3))

            // My team scoring
            scoringButtons(isMyTeam: true)

            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.3))

            // Clock control
            clockControl

            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.3))

            // Opponent scoring
            scoringButtons(isMyTeam: false)

            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.3))

            // End game
            endButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Record Indicator

    private var recordIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .fill(Color.red.opacity(0.5))
                        .scaleEffect(recordingManager.isRecording ? 1.5 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingManager.isRecording)
                )

            Text("REC")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
        }
    }

    // MARK: - Scoring Buttons

    private func scoringButtons(isMyTeam: Bool) -> some View {
        HStack(spacing: 8) {
            scoreButton(points: 1, isMyTeam: isMyTeam)
            scoreButton(points: 2, isMyTeam: isMyTeam)
            scoreButton(points: 3, isMyTeam: isMyTeam)
        }
    }

    private func scoreButton(points: Int, isMyTeam: Bool) -> some View {
        Button {
            addScore(points: points, isMyTeam: isMyTeam)
        } label: {
            Text("+\(points)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isMyTeam ? Color.orange : Color.blue.opacity(0.8))
                )
        }
    }

    // MARK: - Clock Control

    private var clockControl: some View {
        Button {
            toggleClock()
        } label: {
            Image(systemName: isClockRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isClockRunning ? Color.yellow.opacity(0.8) : Color.green.opacity(0.8))
                )
        }
        .contextMenu {
            Button("Next Quarter") {
                nextQuarter()
            }
            Button("Reset Clock") {
                resetClock()
            }
        }
    }

    // MARK: - End Button

    private var endButton: some View {
        Button {
            showEndConfirmation = true
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.8))
                )
        }
    }

    // MARK: - End Confirmation

    private var endGameConfirmation: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if isFinishingRecording {
                    // Finishing state
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Finishing recording...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("\(appState.currentGame?.teamName ?? "Home") \(myScore) - \(opponentScore) \(appState.currentGame?.opponent ?? "Away")")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                } else {
                    // Confirmation state
                    Text("End Game?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("\(appState.currentGame?.teamName ?? "Home") \(myScore) - \(opponentScore) \(appState.currentGame?.opponent ?? "Away")")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    HStack(spacing: 20) {
                        Button("Cancel") {
                            showEndConfirmation = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button("End & Save") {
                            endGame()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Clock String

    private var clockString: String {
        let totalSeconds = (quarterLength * 60) - clockSeconds
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Actions

    private func startRecording() {
        debugPrint("🎬 Starting recording and timeline tracking...")

        recordingManager.startRecording()
        gimbalManager.startTracking()

        // Start timeline tracking for post-processing overlay
        let homeTeam = appState.currentGame?.teamName ?? "Home"
        let awayTeam = appState.currentGame?.opponent ?? "Away"
        timelineTracker.startRecording(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            quarterLength: quarterLength
        )

        debugPrint("🎬 Recording started for \(homeTeam) vs \(awayTeam)")
    }

    private func stopRecording() {
        // Called from onDisappear as cleanup
        clockTimer?.invalidate()
        gimbalManager.stopTracking()
        // Don't stop recording here - let endGame handle it properly
        // This is just for cleanup if view disappears unexpectedly
        if recordingManager.isRecording {
            recordingManager.stopRecording()
        }
    }

    private func addScore(points: Int, isMyTeam: Bool) {
        if isMyTeam {
            myScore += points
        } else {
            opponentScore += points
        }

        // Log score event
        let event = ScoreEvent(
            timestamp: recordingManager.recordingDuration,
            team: isMyTeam ? .my : .opponent,
            points: points,
            quarter: currentQuarter,
            myScoreAfter: myScore,
            opponentScoreAfter: opponentScore
        )

        appState.currentGame?.scoreEvents.append(event)

        // Update timeline tracker for post-processing
        timelineTracker.updateScore(homeScore: myScore, awayScore: opponentScore)

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    private func toggleClock() {
        if isClockRunning {
            clockTimer?.invalidate()
            isClockRunning = false
        } else {
            isClockRunning = true
            clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
                clockSeconds += 1

                // Update timeline tracker with current clock
                timelineTracker.updateClock(clockTime: clockString, quarter: currentQuarter)

                // Check for quarter end
                if clockSeconds >= quarterLength * 60 {
                    clockTimer?.invalidate()
                    isClockRunning = false
                    // Auto-advance quarter?
                }
            }
        }
    }

    private func nextQuarter() {
        if currentQuarter < 4 {
            currentQuarter += 1
            clockSeconds = 0
            isClockRunning = false
            clockTimer?.invalidate()
        }
    }

    private func resetClock() {
        clockSeconds = 0
        isClockRunning = false
        clockTimer?.invalidate()
    }

    private func endGame() {
        // Show finishing state
        isFinishingRecording = true

        // Stop timeline tracker and get the timeline
        let timeline = timelineTracker.stopRecording()

        // Store timeline in RecordingManager for post-processing
        recordingManager.scoreTimeline = timeline

        // Stop gimbal tracking
        clockTimer?.invalidate()
        gimbalManager.stopTracking()

        // Update game with final scores
        appState.currentGame?.myScore = myScore
        appState.currentGame?.opponentScore = opponentScore
        appState.currentGame?.currentQuarter = currentQuarter

        // Wait for video file to be fully written before navigating
        Task {
            debugPrint("Waiting for video file to finish writing...")
            let _ = await recordingManager.stopRecordingAndWait()
            debugPrint("Video file ready, navigating to summary...")

            await MainActor.run {
                isFinishingRecording = false
                appState.endGame()
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? CameraPreviewUIView else { return }
        view.previewLayer?.frame = view.bounds
    }
}

// Custom UIView that properly handles preview layer resizing
class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

#Preview {
    RecordingView()
        .environmentObject(AppState())
}
