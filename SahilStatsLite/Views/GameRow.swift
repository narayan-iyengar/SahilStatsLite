//
//  GameRow.swift
//  SahilStatsLite
//
//  PURPOSE: Game log row component showing result indicator, opponent, team name,
//           date, score, YouTube status, and Sahil's points.
//  KEY TYPES: GameRow
//  DEPENDS ON: Game
//
//  NOTE: Keep this header updated when modifying this file.
//

import SwiftUI

// MARK: - Game Row

struct GameRow: View {
    let game: Game

    var body: some View {
        HStack {
            // Result indicator
            Text(game.resultString)
                .font(.headline)
                .foregroundColor(game.isWin ? .green : game.isLoss ? .red : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(game.opponent)")
                    .font(.headline)
                    .foregroundColor(.primary)

                if !game.teamName.isEmpty {
                    Text(game.teamName)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }

                Text(game.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Score and points
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.scoreString)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                HStack(spacing: 4) {
                    // Video status: local → cloud → uploaded
                    if game.youtubeStatus == .uploading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if game.youtubeStatus == .uploaded {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if game.youtubeStatus == .failed {
                        Image(systemName: "exclamationmark.icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else if game.videoURL != nil {
                        Image(systemName: "film")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("\(game.playerStats.points) pts")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}
