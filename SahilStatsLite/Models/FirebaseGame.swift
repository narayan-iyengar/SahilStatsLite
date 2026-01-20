//
//  FirebaseGame.swift
//  SahilStatsLite
//
//  Maps between Lite's Game model and Firebase document structure (matching main app)
//

import Foundation
import FirebaseFirestore

/// Represents a game document in Firebase (matching main app's schema)
struct FirebaseGame: Codable {
    // MARK: - Firebase Document ID
    @DocumentID var id: String?

    // MARK: - Game Info (matching main app field names)
    var teamName: String
    var opponent: String
    var location: String?
    var season: String?

    // Scores (main app uses myTeamScore, Lite uses myScore)
    var myTeamScore: Int
    var opponentScore: Int
    var outcome: String // "W", "L", or "T"

    // Game format
    var gameFormat: String // "halves" or "quarters"
    var quarterLength: Int
    var numQuarter: Int
    var status: String // "final"

    // MARK: - Player Stats (main app uses short field names)
    var points: Int
    var fg2m: Int
    var fg2a: Int
    var fg3m: Int
    var fg3a: Int
    var ftm: Int
    var fta: Int
    var rebounds: Int
    var assists: Int
    var steals: Int
    var blocks: Int
    var fouls: Int
    var turnovers: Int

    // MARK: - Timestamps
    @ServerTimestamp var timestamp: Date?
    @ServerTimestamp var createdAt: Date?

    // MARK: - Conversion from Lite Game

    init(from game: Game) {
        self.id = game.id
        self.teamName = game.teamName
        self.opponent = game.opponent
        self.location = game.location
        self.season = nil // Lite doesn't track seasons

        // Map scores (Lite uses myScore, Firebase uses myTeamScore)
        self.myTeamScore = game.myScore
        self.opponentScore = game.opponentScore

        // Determine outcome
        if game.myScore > game.opponentScore {
            self.outcome = "W"
        } else if game.myScore < game.opponentScore {
            self.outcome = "L"
        } else {
            self.outcome = "T"
        }

        // Game format (Lite uses halves)
        self.gameFormat = "halves"
        self.quarterLength = game.halfLength
        self.numQuarter = game.totalHalves
        self.status = "final"

        // Map player stats (Lite uses long names, Firebase uses short)
        let stats = game.playerStats
        self.points = stats.points
        self.fg2m = stats.fg2Made
        self.fg2a = stats.fg2Attempted
        self.fg3m = stats.fg3Made
        self.fg3a = stats.fg3Attempted
        self.ftm = stats.ftMade
        self.fta = stats.ftAttempted
        self.rebounds = stats.rebounds
        self.assists = stats.assists
        self.steals = stats.steals
        self.blocks = stats.blocks
        self.fouls = stats.fouls
        self.turnovers = stats.turnovers

        // Timestamps
        self.timestamp = game.date
        self.createdAt = game.createdAt
    }

    // MARK: - Conversion to Lite Game

    func toGame() -> Game {
        return Game(
            id: id ?? UUID().uuidString,
            opponent: opponent,
            teamName: teamName,
            location: location,
            date: timestamp ?? Date(),
            myScore: myTeamScore,
            opponentScore: opponentScore,
            halfLength: quarterLength,
            currentHalf: numQuarter,
            totalHalves: numQuarter,
            playerStats: PlayerStats(
                fg2Made: fg2m,
                fg2Attempted: fg2a,
                fg3Made: fg3m,
                fg3Attempted: fg3a,
                ftMade: ftm,
                ftAttempted: fta,
                assists: assists,
                rebounds: rebounds,
                steals: steals,
                blocks: blocks,
                turnovers: turnovers,
                fouls: fouls
            ),
            createdAt: createdAt ?? Date()
        )
    }

    // MARK: - Convert to Firestore Data (for writes)

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "teamName": teamName,
            "opponent": opponent,
            "myTeamScore": myTeamScore,
            "opponentScore": opponentScore,
            "outcome": outcome,
            "gameFormat": gameFormat,
            "quarterLength": quarterLength,
            "numQuarter": numQuarter,
            "status": status,
            "points": points,
            "fg2m": fg2m,
            "fg2a": fg2a,
            "fg3m": fg3m,
            "fg3a": fg3a,
            "ftm": ftm,
            "fta": fta,
            "rebounds": rebounds,
            "assists": assists,
            "steals": steals,
            "blocks": blocks,
            "fouls": fouls,
            "turnovers": turnovers,
            "achievements": [] // Empty array for Lite games
        ]

        if let location = location, !location.isEmpty {
            data["location"] = location
        }

        if let season = season {
            data["season"] = season
        }

        // Handle timestamps
        if let timestamp = timestamp {
            data["timestamp"] = Timestamp(date: timestamp)
        } else {
            data["timestamp"] = FieldValue.serverTimestamp()
        }

        if let createdAt = createdAt {
            data["createdAt"] = Timestamp(date: createdAt)
        } else {
            data["createdAt"] = FieldValue.serverTimestamp()
        }

        return data
    }
}
