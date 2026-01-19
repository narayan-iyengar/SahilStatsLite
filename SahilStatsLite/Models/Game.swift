//
//  Game.swift
//  SahilStatsLite
//
//  Simplified game model for recording and score tracking
//

import Foundation
import SwiftUI

// MARK: - Game Model

struct Game: Identifiable, Codable {
    let id: String
    var opponent: String
    var teamName: String
    var location: String?
    var date: Date

    // Scores
    var myScore: Int = 0
    var opponentScore: Int = 0

    // Game structure - AAU uses halves (18 or 20 minutes)
    var halfLength: Int = 18 // minutes (AAU: 18 or 20)
    var currentHalf: Int = 1
    var totalHalves: Int = 2

    // Legacy support (for compatibility)
    var quarterLength: Int { halfLength }
    var currentQuarter: Int {
        get { currentHalf }
        set { currentHalf = newValue }
    }

    // Video
    var videoURL: URL?
    var videoDuration: TimeInterval?

    // Score timeline for overlay
    var scoreEvents: [ScoreEvent] = []

    // Player stats (Sahil)
    var playerStats: PlayerStats = PlayerStats()

    // Timestamps
    var createdAt: Date = Date()
    var completedAt: Date?

    init(opponent: String, teamName: String = "Wildcats", location: String? = nil) {
        self.id = UUID().uuidString
        self.opponent = opponent
        self.teamName = teamName
        self.location = location
        self.date = Date()
    }

    // MARK: - Computed Properties

    var isWin: Bool {
        myScore > opponentScore
    }

    var isLoss: Bool {
        opponentScore > myScore
    }

    var isTie: Bool {
        myScore == opponentScore
    }

    var resultString: String {
        if isWin { return "W" }
        if isLoss { return "L" }
        return "T"
    }

    var scoreString: String {
        "\(myScore) - \(opponentScore)"
    }

    var displayTitle: String {
        "vs \(opponent)"
    }
}

// MARK: - Player Stats (Sahil)

struct PlayerStats: Codable, Equatable {
    // Shooting stats
    var fg2Made: Int = 0
    var fg2Attempted: Int = 0
    var fg3Made: Int = 0
    var fg3Attempted: Int = 0
    var ftMade: Int = 0
    var ftAttempted: Int = 0

    // Other stats
    var assists: Int = 0
    var rebounds: Int = 0
    var steals: Int = 0
    var blocks: Int = 0
    var turnovers: Int = 0
    var fouls: Int = 0

    // MARK: - Computed Properties

    var points: Int {
        (fg2Made * 2) + (fg3Made * 3) + ftMade
    }

    var totalFGMade: Int { fg2Made + fg3Made }
    var totalFGAttempted: Int { fg2Attempted + fg3Attempted }

    var fgPercentage: Double {
        totalFGAttempted > 0 ? Double(totalFGMade) / Double(totalFGAttempted) * 100 : 0
    }

    var fg2Percentage: Double {
        fg2Attempted > 0 ? Double(fg2Made) / Double(fg2Attempted) * 100 : 0
    }

    var fg3Percentage: Double {
        fg3Attempted > 0 ? Double(fg3Made) / Double(fg3Attempted) * 100 : 0
    }

    var ftPercentage: Double {
        ftAttempted > 0 ? Double(ftMade) / Double(ftAttempted) * 100 : 0
    }

    // Advanced stats
    var efgPercentage: Double {
        // eFG% = (FGM + 0.5 * 3PM) / FGA
        totalFGAttempted > 0 ? (Double(totalFGMade) + 0.5 * Double(fg3Made)) / Double(totalFGAttempted) * 100 : 0
    }

    var tsPercentage: Double {
        // TS% = PTS / (2 * (FGA + 0.44 * FTA))
        let denominator = 2 * (Double(totalFGAttempted) + 0.44 * Double(ftAttempted))
        return denominator > 0 ? Double(points) / denominator * 100 : 0
    }
}

// MARK: - Score Event

struct ScoreEvent: Identifiable, Codable {
    let id: String
    let timestamp: TimeInterval // seconds from recording start
    let team: Team
    let points: Int
    let quarter: Int
    let myScoreAfter: Int
    let opponentScoreAfter: Int

    init(timestamp: TimeInterval, team: Team, points: Int, quarter: Int, myScoreAfter: Int, opponentScoreAfter: Int) {
        self.id = UUID().uuidString
        self.timestamp = timestamp
        self.team = team
        self.points = points
        self.quarter = quarter
        self.myScoreAfter = myScoreAfter
        self.opponentScoreAfter = opponentScoreAfter
    }

    enum Team: String, Codable {
        case my
        case opponent
    }
}

// MARK: - Quarter

struct Quarter: Identifiable {
    let id: Int
    let number: Int
    var startTime: TimeInterval?
    var endTime: TimeInterval?

    var displayName: String {
        "Q\(number)"
    }
}

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case stopped
}

// MARK: - Clock State

enum ClockState: Equatable {
    case stopped
    case running
    case paused
}
