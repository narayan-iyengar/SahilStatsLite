//
//  RecordingView.swift
//  SahilStatsLite
//
//  Full-screen recording view with floating controls
//  Real-time scoreboard overlay burned into video (like ScoreCam)
//

import SwiftUI
import AVFoundation
import UIKit

struct RecordingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var gimbalManager = GimbalTrackingManager.shared

    // Game state
    @State private var myScore: Int = 0
    @State private var opponentScore: Int = 0
    @State private var currentHalf: Int = 1
    @State private var clockSeconds: Int = 0
    @State private var isClockRunning: Bool = false
    @State private var clockTimer: Timer?

    // UI state
    @State private var showEndConfirmation: Bool = false
    @State private var isFinishingRecording: Bool = false
    @State private var isPortrait: Bool = true
    @State private var hasStartedRecording: Bool = false

    private var halfLength: Int {
        appState.currentGame?.halfLength ?? 18
    }

    private var clockString: String {
        let totalSeconds = (halfLength * 60) - clockSeconds
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var periodString: String {
        return currentHalf == 1 ? "1st" : "2nd"
    }

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            cameraPreview

            // Scoreboard overlay (mirrors what's burned into video)
            if !isPortrait {
                VStack {
                    Spacer()
                    scoreboardOverlay
                        .padding(.horizontal, 30)
                        .padding(.bottom, 30)
                }
            }

            // Floating controls (only in landscape)
            if !isPortrait {
                VStack {
                    Spacer()
                    floatingControlBar
                        .padding(.bottom, 110) // Above the scoreboard
                }
            }

            // End game confirmation
            if showEndConfirmation {
                endGameConfirmation
            }

            // Rotate to landscape prompt (blocking)
            if isPortrait && !recordingManager.isSimulator {
                rotatePromptOverlay
            }
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateOrientationState()
        }
        .task {
            updateOrientationState()
            recordingManager.reset()

            // Initialize overlay with game info
            updateOverlayState()

            await recordingManager.requestPermissionsAndSetup()

            if !isPortrait && recordingManager.isSessionReady && !recordingManager.isSimulator {
                startRecording()
                hasStartedRecording = true
            }
        }
        .onChange(of: isPortrait) { wasPortrait, nowPortrait in
            if wasPortrait && !nowPortrait && !hasStartedRecording {
                if recordingManager.isSessionReady && !recordingManager.isSimulator {
                    startRecording()
                    hasStartedRecording = true
                }
            }
        }
        .onDisappear {
            stopRecording()
            recordingManager.stopSession()
        }
    }

    // MARK: - Camera Preview

    @ViewBuilder
    private var cameraPreview: some View {
        if recordingManager.isSimulator {
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
    }

    // MARK: - Floating Control Bar

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
            Button("Next Half") {
                nextHalf()
            }
            Button("Reset Clock") {
                resetClock()
            }
        }
    }

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

    // MARK: - Scoreboard Overlay (mirrors the burned-in overlay)

    private var scoreboardOverlay: some View {
        HStack(spacing: 0) {
            // Home team name
            Text((appState.currentGame?.teamName ?? "Home").uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)

            // Home score
            Text("\(myScore)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 50)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .cornerRadius(4)

            // Period and clock
            VStack(spacing: 2) {
                Text(periodString)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
                Text(clockString)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 60)

            // Away score
            Text("\(opponentScore)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 50)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .cornerRadius(4)

            // Away team name
            Text((appState.currentGame?.opponent ?? "Away").uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.85))
        )
    }

    // MARK: - End Confirmation

    private var endGameConfirmation: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if isFinishingRecording {
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

    // MARK: - Rotate Prompt

    private var rotatePromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "rotate.right.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(-90))

                Text("Rotate to Landscape")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Hold your phone horizontally\nto start recording")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .transition(.opacity)
    }

    // MARK: - Orientation Detection

    private func updateOrientationState() {
        let orientation = UIDevice.current.orientation

        switch orientation {
        case .landscapeLeft, .landscapeRight:
            withAnimation {
                isPortrait = false
            }
        case .portrait, .portraitUpsideDown:
            withAnimation {
                isPortrait = true
            }
        default:
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let interfaceOrientation = windowScene.effectiveGeometry.interfaceOrientation
                withAnimation {
                    isPortrait = interfaceOrientation.isPortrait
                }
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        debugPrint("🎬 Starting recording...")

        // Initialize overlay state before recording
        updateOverlayState()

        recordingManager.startRecording()
        gimbalManager.startTracking()

        debugPrint("🎬 Recording started for \(appState.currentGame?.teamName ?? "Home") vs \(appState.currentGame?.opponent ?? "Away")")
    }

    private func stopRecording() {
        clockTimer?.invalidate()
        gimbalManager.stopTracking()
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
            quarter: currentHalf,
            myScoreAfter: myScore,
            opponentScoreAfter: opponentScore
        )
        appState.currentGame?.scoreEvents.append(event)

        // Update the real-time overlay
        updateOverlayState()

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
            clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                clockSeconds += 1
                updateOverlayState()

                if clockSeconds >= halfLength * 60 {
                    clockTimer?.invalidate()
                    isClockRunning = false
                }
            }
        }
    }

    private func nextHalf() {
        if currentHalf < 2 {
            currentHalf += 1
            clockSeconds = 0
            isClockRunning = false
            clockTimer?.invalidate()
            updateOverlayState()
        }
    }

    private func resetClock() {
        clockSeconds = 0
        isClockRunning = false
        clockTimer?.invalidate()
        updateOverlayState()
    }

    private func updateOverlayState() {
        recordingManager.updateOverlay(
            homeTeam: appState.currentGame?.teamName ?? "Home",
            awayTeam: appState.currentGame?.opponent ?? "Away",
            homeScore: myScore,
            awayScore: opponentScore,
            period: periodString,
            clockTime: clockString,
            eventName: ""  // Can add tournament name later
        )
    }

    private func endGame() {
        isFinishingRecording = true

        clockTimer?.invalidate()
        gimbalManager.stopTracking()

        appState.currentGame?.myScore = myScore
        appState.currentGame?.opponentScore = opponentScore
        appState.currentGame?.currentHalf = currentHalf

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

        view.updatePreviewOrientation()

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? CameraPreviewUIView else { return }
        view.previewLayer?.frame = view.bounds
        view.updatePreviewOrientation()
    }
}

class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        updatePreviewOrientation()
    }

    func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection else { return }

        let deviceOrientation = UIDevice.current.orientation
        let rotationAngle: CGFloat

        switch deviceOrientation {
        case .portrait:
            rotationAngle = 90
        case .portraitUpsideDown:
            rotationAngle = 270
        case .landscapeLeft:
            rotationAngle = 0
        case .landscapeRight:
            rotationAngle = 180
        default:
            if let windowScene = window?.windowScene {
                switch windowScene.effectiveGeometry.interfaceOrientation {
                case .portrait:
                    rotationAngle = 90
                case .portraitUpsideDown:
                    rotationAngle = 270
                case .landscapeLeft:
                    rotationAngle = 0
                case .landscapeRight:
                    rotationAngle = 180
                default:
                    rotationAngle = 0
                }
            } else {
                rotationAngle = 0
            }
        }

        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(AppState())
}
