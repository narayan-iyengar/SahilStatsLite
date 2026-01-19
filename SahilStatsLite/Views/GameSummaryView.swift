//
//  GameSummaryView.swift
//  SahilStatsLite
//
//  Post-game summary with final score and video
//  Video already has scoreboard overlay burned in (real-time)
//

import SwiftUI
import Photos

struct GameSummaryView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var recordingManager = RecordingManager.shared

    // Save state
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var saveError: String?

    var game: Game? {
        appState.currentGame
    }

    var videoURL: URL? {
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

                if videoURL != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Ready")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .aspectRatio(16/9, contentMode: .fit)

                if videoURL != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.5))
                        Text("No video recorded")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            // Status messages
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
            // Share
            if let url = videoURL {
                ShareLink(item: url) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Video")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
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
                    Text(saveSuccess ? "Saved!" : "Save to Photos")
                }
                .font(.headline)
                .foregroundColor(saveSuccess ? .green : .blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(saveSuccess ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(isSaving || saveSuccess || videoURL == nil)

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

    // MARK: - Save to Photos

    private func saveToPhotos() {
        guard let url = videoURL else {
            saveError = "No video to save"
            return
        }

        isSaving = true
        saveError = nil

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
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugPrint("❌ Video file doesn't exist at: \(url.path)")
            return false
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
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
