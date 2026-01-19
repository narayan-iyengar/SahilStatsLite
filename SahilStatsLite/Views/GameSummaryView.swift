//
//  GameSummaryView.swift
//  SahilStatsLite
//
//  Post-game summary with stats - auto-saves video to Photos
//

import SwiftUI
import Photos

struct GameSummaryView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var recordingManager = RecordingManager.shared

    // Save state
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus {
        case idle
        case saving
        case saved
        case failed(String)
    }

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

                // Player Stats (Sahil's performance)
                if let game = game {
                    playerStatsSection(stats: game.playerStats)
                }

                // Save status (minimal)
                saveStatusView

                // Done button
                doneButton

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .task {
            // Auto-save video to Photos when view appears
            await autoSaveVideo()
        }
    }

    // MARK: - Auto Save

    private func autoSaveVideo() async {
        guard let url = videoURL else {
            saveStatus = .saved // No video, nothing to save - that's fine
            return
        }

        saveStatus = .saving

        let success = await saveVideoToLibrary(url: url)
        await MainActor.run {
            if success {
                saveStatus = .saved
            } else {
                saveStatus = .failed("Couldn't save to Photos")
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
        if game.isWin { return "🏆" }
        if game.isLoss { return "💪" }
        return "🤝"
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

    // MARK: - Player Stats Section

    private func playerStatsSection(stats: PlayerStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sahil's Performance")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                // Main Stats Row
                HStack(spacing: 0) {
                    statBox(value: "\(stats.points)", label: "PTS", color: .orange)
                    statBox(value: "\(stats.rebounds)", label: "REB", color: .blue)
                    statBox(value: "\(stats.assists)", label: "AST", color: .green)
                    statBox(value: "\(stats.steals)", label: "STL", color: .purple)
                    statBox(value: "\(stats.blocks)", label: "BLK", color: .red)
                }

                Divider()

                // Shooting Stats
                VStack(spacing: 12) {
                    Text("Shooting")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        shootingStat(
                            label: "2PT",
                            made: stats.fg2Made,
                            attempted: stats.fg2Attempted,
                            percentage: stats.fg2Percentage
                        )
                        shootingStat(
                            label: "3PT",
                            made: stats.fg3Made,
                            attempted: stats.fg3Attempted,
                            percentage: stats.fg3Percentage
                        )
                        shootingStat(
                            label: "FT",
                            made: stats.ftMade,
                            attempted: stats.ftAttempted,
                            percentage: stats.ftPercentage
                        )
                    }

                    // Advanced stats row
                    HStack(spacing: 24) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f%%", stats.fgPercentage))
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("FG%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f%%", stats.efgPercentage))
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("eFG%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f%%", stats.tsPercentage))
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("TS%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                // Other Stats
                if stats.turnovers > 0 || stats.fouls > 0 {
                    Divider()
                    HStack(spacing: 24) {
                        if stats.turnovers > 0 {
                            HStack(spacing: 4) {
                                Text("\(stats.turnovers)")
                                    .fontWeight(.semibold)
                                Text("TO")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                        }
                        if stats.fouls > 0 {
                            HStack(spacing: 4) {
                                Text("\(stats.fouls)")
                                    .fontWeight(.semibold)
                                Text("PF")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
    }

    private func statBox(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func shootingStat(label: String, made: Int, attempted: Int, percentage: Double) -> some View {
        VStack(spacing: 4) {
            Text("\(made)/\(attempted)")
                .font(.headline)
                .monospacedDigit()
            Text(String(format: "%.0f%%", percentage))
                .font(.caption)
                .foregroundColor(percentage >= 50 ? .green : percentage >= 33 ? .orange : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Save Status

    private var saveStatusView: some View {
        Group {
            switch saveStatus {
            case .idle:
                EmptyView()
            case .saving:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Saving video...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            case .saved:
                Label("Video saved to Photos", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            appState.goHome()
        } label: {
            Text("Done")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.orange)
                .cornerRadius(12)
        }
    }
}

#Preview {
    let appState = AppState()
    appState.currentGame = Game(opponent: "Thunder", teamName: "Wildcats")
    appState.currentGame?.myScore = 24
    appState.currentGame?.opponentScore = 18

    // Add sample player stats
    appState.currentGame?.playerStats = PlayerStats(
        fg2Made: 4,
        fg2Attempted: 8,
        fg3Made: 2,
        fg3Attempted: 5,
        ftMade: 3,
        ftAttempted: 4,
        assists: 3,
        rebounds: 5,
        steals: 2,
        blocks: 1,
        turnovers: 2,
        fouls: 1
    )

    return GameSummaryView()
        .environmentObject(appState)
}
