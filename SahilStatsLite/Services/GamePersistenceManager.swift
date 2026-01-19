//
//  GamePersistenceManager.swift
//  SahilStatsLite
//
//  Handles saving and loading games to/from disk
//

import Foundation
import SwiftUI
import Combine

@MainActor
class GamePersistenceManager: ObservableObject {
    static let shared = GamePersistenceManager()

    @Published private(set) var savedGames: [Game] = []

    private let fileManager = FileManager.default

    private var gamesFileURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("games.json")
    }

    private init() {
        loadGames()
    }

    // MARK: - Load

    func loadGames() {
        guard fileManager.fileExists(atPath: gamesFileURL.path) else {
            savedGames = []
            return
        }

        do {
            let data = try Data(contentsOf: gamesFileURL)
            let decoder = JSONDecoder()
            savedGames = try decoder.decode([Game].self, from: data)
            savedGames.sort { $0.date > $1.date } // Most recent first
            debugPrint("[GamePersistence] Loaded \(savedGames.count) games")
        } catch {
            debugPrint("[GamePersistence] Failed to load games: \(error)")
            savedGames = []
        }
    }

    // MARK: - Save

    func saveGame(_ game: Game) {
        var games = savedGames

        // Update existing or add new
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games[index] = game
        } else {
            games.insert(game, at: 0)
        }

        saveAllGames(games)
    }

    private func saveAllGames(_ games: [Game]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(games)
            try data.write(to: gamesFileURL)
            savedGames = games
            debugPrint("[GamePersistence] Saved \(games.count) games")
        } catch {
            debugPrint("[GamePersistence] Failed to save games: \(error)")
        }
    }

    // MARK: - Delete

    func deleteGame(_ game: Game) {
        savedGames.removeAll { $0.id == game.id }
        saveAllGames(savedGames)
    }

    func deleteGame(at offsets: IndexSet) {
        var games = savedGames
        games.remove(atOffsets: offsets)
        saveAllGames(games)
    }

    // MARK: - Career Stats

    var careerGames: Int { savedGames.count }

    var careerWins: Int {
        savedGames.filter { $0.isWin }.count
    }

    var careerLosses: Int {
        savedGames.filter { $0.isLoss }.count
    }

    var careerTies: Int {
        savedGames.filter { $0.isTie }.count
    }

    var careerRecord: String {
        if careerTies > 0 {
            return "\(careerWins)-\(careerLosses)-\(careerTies)"
        }
        return "\(careerWins)-\(careerLosses)"
    }

    // Points
    var careerTotalPoints: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.points }
    }

    var careerPPG: Double {
        careerGames > 0 ? Double(careerTotalPoints) / Double(careerGames) : 0
    }

    // Rebounds
    var careerTotalRebounds: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.rebounds }
    }

    var careerRPG: Double {
        careerGames > 0 ? Double(careerTotalRebounds) / Double(careerGames) : 0
    }

    // Assists
    var careerTotalAssists: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.assists }
    }

    var careerAPG: Double {
        careerGames > 0 ? Double(careerTotalAssists) / Double(careerGames) : 0
    }

    // Steals
    var careerTotalSteals: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.steals }
    }

    var careerSPG: Double {
        careerGames > 0 ? Double(careerTotalSteals) / Double(careerGames) : 0
    }

    // Blocks
    var careerTotalBlocks: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.blocks }
    }

    var careerBPG: Double {
        careerGames > 0 ? Double(careerTotalBlocks) / Double(careerGames) : 0
    }

    // Shooting
    var careerFGMade: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.totalFGMade }
    }

    var careerFGAttempted: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.totalFGAttempted }
    }

    var careerFGPercentage: Double {
        careerFGAttempted > 0 ? Double(careerFGMade) / Double(careerFGAttempted) * 100 : 0
    }

    var career3PMade: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.fg3Made }
    }

    var career3PAttempted: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.fg3Attempted }
    }

    var career3PPercentage: Double {
        career3PAttempted > 0 ? Double(career3PMade) / Double(career3PAttempted) * 100 : 0
    }

    var careerFTMade: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.ftMade }
    }

    var careerFTAttempted: Int {
        savedGames.reduce(0) { $0 + $1.playerStats.ftAttempted }
    }

    var careerFTPercentage: Double {
        careerFTAttempted > 0 ? Double(careerFTMade) / Double(careerFTAttempted) * 100 : 0
    }
}
