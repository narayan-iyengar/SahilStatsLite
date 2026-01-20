//
//  FirebaseService.swift
//  SahilStatsLite
//
//  Firebase Firestore sync service for games
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()

    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published var error: String?
    @Published private(set) var lastSyncTime: Date?

    private let db = Firestore.firestore()
    private var gamesListener: ListenerRegistration?

    // Callback for when games are updated from Firebase
    var onGamesUpdated: (([Game]) -> Void)?

    private init() {
        configureFirestore()
    }

    // MARK: - Configuration

    private func configureFirestore() {
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
        debugPrint("[FirebaseService] Firestore configured")
    }

    // MARK: - Real-time Listener

    func startListening() {
        guard gamesListener == nil else {
            debugPrint("[FirebaseService] Already listening")
            return
        }

        isSyncing = true
        debugPrint("[FirebaseService] Starting games listener...")

        gamesListener = db.collection("games")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleGamesSnapshot(snapshot: snapshot, error: error)
                }
            }
    }

    func stopListening() {
        gamesListener?.remove()
        gamesListener = nil
        isSyncing = false
        debugPrint("[FirebaseService] Stopped listening")
    }

    private func handleGamesSnapshot(snapshot: QuerySnapshot?, error: Error?) {
        if let error = error {
            self.error = error.localizedDescription
            debugPrint("[FirebaseService] Listener error: \(error)")
            isSyncing = false
            return
        }

        guard let documents = snapshot?.documents else {
            debugPrint("[FirebaseService] No documents in snapshot")
            isSyncing = false
            return
        }

        let newGames = documents.compactMap { document -> Game? in
            do {
                var firebaseGame = try document.data(as: FirebaseGame.self)
                firebaseGame.id = document.documentID
                return firebaseGame.toGame()
            } catch {
                debugPrint("[FirebaseService] Error decoding game \(document.documentID): \(error)")
                return nil
            }
        }

        games = newGames
        lastSyncTime = Date()
        isSyncing = false
        debugPrint("[FirebaseService] Loaded \(newGames.count) games from Firebase")

        // Notify callback
        onGamesUpdated?(newGames)
    }

    // MARK: - CRUD Operations

    /// Save a game to Firebase
    func saveGame(_ game: Game) async throws {
        isLoading = true
        defer { isLoading = false }

        let firebaseGame = FirebaseGame(from: game)
        let data = firebaseGame.toFirestoreData()

        if let existingId = game.id.isEmpty ? nil : game.id {
            // Check if document exists
            let docRef = db.collection("games").document(existingId)
            let docSnapshot = try await docRef.getDocument()

            if docSnapshot.exists {
                // Update existing
                try await docRef.setData(data, merge: true)
                debugPrint("[FirebaseService] Updated game: \(existingId)")
            } else {
                // Create with specific ID
                try await docRef.setData(data)
                debugPrint("[FirebaseService] Created game with ID: \(existingId)")
            }
        } else {
            // Create new document
            let docRef = try await db.collection("games").addDocument(data: data)
            debugPrint("[FirebaseService] Created new game: \(docRef.documentID)")
        }
    }

    /// Delete a game from Firebase
    func deleteGame(_ gameId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        try await db.collection("games").document(gameId).delete()
        debugPrint("[FirebaseService] Deleted game: \(gameId)")
    }

    /// Fetch all games once (for initial sync)
    func fetchAllGames() async throws -> [Game] {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("games")
            .order(by: "timestamp", descending: true)
            .getDocuments()

        let games = snapshot.documents.compactMap { document -> Game? in
            do {
                var firebaseGame = try document.data(as: FirebaseGame.self)
                firebaseGame.id = document.documentID
                return firebaseGame.toGame()
            } catch {
                debugPrint("[FirebaseService] Error decoding game \(document.documentID): \(error)")
                return nil
            }
        }

        debugPrint("[FirebaseService] Fetched \(games.count) games")
        return games
    }

    // MARK: - Sync Status

    var isConnected: Bool {
        gamesListener != nil
    }

    deinit {
        gamesListener?.remove()
    }
}
