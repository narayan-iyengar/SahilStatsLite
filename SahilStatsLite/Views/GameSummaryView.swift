//
//  GameSummaryView.swift
//  SahilStatsLite
//
//  Post-game summary with final score and video
//

import SwiftUI
import Combine
import Photos

struct GameSummaryView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var recordingManager = RecordingManager.shared

    // Processing state
    @State private var isProcessing = true
    @State private var processingProgress: String = "Processing video..."
    @State private var processedVideoURL: URL?
    @State private var processingError: String?

    // Save state
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var saveError: String?

    var game: Game? {
        appState.currentGame
    }

    var rawVideoURL: URL? {
        recordingManager.getRecordingURL()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Result Header
                resultHeader

                // Score Card
                scoreCard

                // Video Preview
                videoPreviewSection

                // Actions
                actionButtons

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .task {
            await processVideoWithOverlay()
        }
    }

    // MARK: - Result Header

    private var resultHeader: some View {
        VStack(spacing: 8) {
            Text(resultEmoji)
                .font(.system(size: 60))

            Text(resultText)
                .font(.title)
                .fontWeight(.bold)

            if let game = game {
                Text(game.date, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 20)
    }

    private var resultEmoji: String {
        guard let game = game else { return "" }
        if game.isWin { return "" }
        if game.isLoss { return "" }
        return ""
    }

    private var resultText: String {
        guard let game = game else { return "" }
        if game.isWin { return "Victory!" }
        if game.isLoss { return "Tough Loss" }
        return "Tie Game"
    }

    // MARK: - Score Card

    private var scoreCard: some View {
        HStack(spacing: 0) {
            // My Team
            VStack(spacing: 8) {
                Text(game?.teamName ?? "Home")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("\(game?.myScore ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)

            // VS
            Text("-")
                .font(.title)
                .foregroundColor(.secondary)

            // Opponent
            VStack(spacing: 8) {
                Text(game?.opponent ?? "Away")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("\(game?.opponentScore ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Video Preview

    private var videoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Game Video")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(processingProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .aspectRatio(16/9, contentMode: .fit)

                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Adding score overlay...")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.subheadline)
                    }
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            // Status messages
            if let error = processingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
            }

            if saveSuccess {
                Label("Saved to Photos!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }

            if let error = saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Share (uses processed video if available)
            if let url = processedVideoURL ?? rawVideoURL {
                ShareLink(item: url) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(processedVideoURL != nil ? "Share Video" : "Share Raw Video")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isProcessing ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)
            }

            // Save to Photos
            Button {
                saveToPhotos()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.blue)
                    } else {
                        Image(systemName: saveSuccess ? "checkmark.circle.fill" : "photo.on.rectangle")
                    }
                    Text(saveSuccess ? "Saved!" : (isProcessing ? "Processing..." : "Save to Photos"))
                }
                .font(.headline)
                .foregroundColor(saveSuccess ? .green : .blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(saveSuccess ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(isSaving || saveSuccess || isProcessing)

            // Done
            Button {
                appState.goHome()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Video Processing

    private func processVideoWithOverlay() async {
        guard let videoURL = rawVideoURL else {
            isProcessing = false
            processingError = "No video recorded"
            debugPrint("❌ No video URL available")
            return
        }

        // Verify file exists and is accessible
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            isProcessing = false
            processingError = "Video file not found"
            debugPrint("❌ Video file doesn't exist at: \(videoURL.path)")
            return
        }

        // Small delay to ensure file is fully flushed to disk
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let timeline = recordingManager.scoreTimeline
        debugPrint("📊 Timeline has \(timeline.count) snapshots")

        // If no timeline, skip processing but allow saving raw video
        guard !timeline.isEmpty else {
            isProcessing = false
            processingError = "No score data - using raw video"
            processedVideoURL = videoURL
            debugPrint("⚠️ No timeline data, using raw video")
            return
        }

        processingProgress = "Adding score overlay..."

        // Run the compositor
        await withCheckedContinuation { continuation in
            OverlayCompositor.addOverlay(to: videoURL, scoreTimeline: timeline) { result in
                switch result {
                case .success(let url):
                    self.processedVideoURL = url
                    self.processingProgress = "Done!"
                    debugPrint("✅ Video processed with overlay: \(url.lastPathComponent)")

                case .failure(let error):
                    self.processingError = "Overlay failed - saving raw video"
                    self.processedVideoURL = videoURL  // Fall back to raw video
                    debugPrint("⚠️ Overlay failed, using raw video: \(error)")
                }

                self.isProcessing = false
                continuation.resume()
            }
        }
    }

    // MARK: - Save to Photos

    private func saveToPhotos() {
        isSaving = true
        saveError = nil

        // Use processed video if available, otherwise raw
        let videoToSave = processedVideoURL ?? rawVideoURL

        guard let url = videoToSave else {
            isSaving = false
            saveError = "No video to save"
            return
        }

        Task {
            let success = await saveVideoToLibrary(url: url)
            await MainActor.run {
                isSaving = false
                if success {
                    saveSuccess = true
                } else {
                    saveError = "Failed to save. Check Photos permission in Settings."
                }
            }
        }
    }

    private func saveVideoToLibrary(url: URL) async -> Bool {
        // Check if file exists first
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugPrint("❌ Video file doesn't exist at: \(url.path)")
            return false
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                debugPrint("📷 Photo library authorization status: \(status.rawValue)")

                // Accept authorized or limited access
                guard status == .authorized || status == .limited else {
                    debugPrint("❌ Photo library access denied: \(status)")
                    continuation.resume(returning: false)
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    if let error = error {
                        debugPrint("❌ Failed to save to photos: \(error)")
                    } else {
                        debugPrint("✅ Video saved to Photos successfully")
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

#Preview {
    let appState = AppState()
    appState.currentGame = Game(opponent: "Thunder", teamName: "Wildcats")
    appState.currentGame?.myScore = 24
    appState.currentGame?.opponentScore = 18

    return GameSummaryView()
        .environmentObject(appState)
}
