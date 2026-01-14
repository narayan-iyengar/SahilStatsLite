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

    // Game structure
    var quarterLength: Int = 6 // minutes
    var currentQuarter: Int = 1
    var totalQuarters: Int = 4

    // Video
    var videoURL: URL?
    var videoDuration: TimeInterval?

    // Score timeline for overlay
    var scoreEvents: [ScoreEvent] = []

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
