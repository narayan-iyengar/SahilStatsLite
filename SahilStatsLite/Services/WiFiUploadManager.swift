//
//  WiFiUploadManager.swift
//  SahilStatsLite
//
//  PURPOSE: Auto-uploads pending game videos when connected to home WiFi.
//           Monitors network for IyengarHomeWifi SSID. On detection, uploads
//           all games with youtubeStatus == .local sequentially. After each
//           successful upload, deletes the inferior stream recording from YouTube.
//  KEY TYPES: WiFiUploadManager (singleton, @MainActor)
//  DEPENDS ON: GamePersistenceManager, YouTubeService
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import Network
import SystemConfiguration.CaptiveNetwork

@MainActor
class WiFiUploadManager: ObservableObject {
    static let shared = WiFiUploadManager()

    @Published var isUploading: Bool = false
    @Published var pendingCount: Int = 0

    private let homeSSID = "IyengarHomeWifi"
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let monitorQueue = DispatchQueue(label: "com.sahilstats.wifimonitor")
    private var isMonitoring = false
    private var lastCheckTime: Date = .distantPast

    private init() {}

    /// Start monitoring for home WiFi. Call once at app launch.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                self?.checkAndUpload()
            }
        }
        monitor.start(queue: monitorQueue)
        debugPrint("[WiFiUpload] Monitoring started")
    }

    /// Check if on home WiFi and upload pending games.
    private func checkAndUpload() {
        // Debounce: don't check more than once per 30 seconds
        guard Date().timeIntervalSince(lastCheckTime) > 30 else { return }
        lastCheckTime = Date()

        guard isOnHomeWiFi() else { return }
        guard !isUploading else { return }
        guard YouTubeService.shared.isAuthorized else { return }

        let pending = pendingGames()
        pendingCount = pending.count
        guard !pending.isEmpty else { return }

        debugPrint("[WiFiUpload] Home WiFi detected, \(pending.count) games to upload")
        isUploading = true

        Task {
            for game in pending {
                await uploadGame(game)
            }
            isUploading = false
            pendingCount = 0
            debugPrint("[WiFiUpload] All uploads complete")
        }
    }

    private func pendingGames() -> [Game] {
        GamePersistenceManager.shared.savedGames.filter { game in
            game.youtubeStatus == .local && game.videoURL != nil && game.completedAt != nil
        }
    }

    private func uploadGame(_ game: Game) async {
        guard let url = resolveVideoURL(for: game) else {
            debugPrint("[WiFiUpload] Skipping \(game.id): video file not found")
            return
        }

        let title = "\(game.teamName) vs \(game.opponent) - \(game.date.formatted(date: .abbreviated, time: .omitted))"
        let description = "\(game.teamName) \(game.myScore) - \(game.opponentScore) \(game.opponent)\n\nRecorded with Sahil Stats"

        debugPrint("[WiFiUpload] Uploading: \(title)")

        // Mark as uploading
        var updatedGame = game
        updatedGame.youtubeStatus = .uploading
        GamePersistenceManager.shared.saveGame(updatedGame)

        // Upload (uses existing background session flow)
        await YouTubeService.shared.uploadVideo(url: url, title: title, description: description, gameID: game.id)

        // The onUploadCompleted callback in GamePersistenceManager handles:
        // - Setting youtubeStatus to .uploaded
        // - Storing youtubeVideoId
        // - Deleting local file
        // We just need to delete the stream recording after success.

        // Wait briefly for the completion handler to fire
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Check if upload succeeded and delete stream recording
        if let updated = GamePersistenceManager.shared.savedGames.first(where: { $0.id == game.id }),
           updated.youtubeStatus == .uploaded,
           let broadcastId = updated.broadcastVideoId {
            debugPrint("[WiFiUpload] Deleting stream recording \(broadcastId)")
            await YouTubeService.shared.deleteVideo(videoId: broadcastId)

            // Clear the broadcastVideoId since it's been deleted
            var cleaned = updated
            cleaned.broadcastVideoId = nil
            GamePersistenceManager.shared.saveGame(cleaned)
        }
    }

    // MARK: - WiFi Detection

    private func isOnHomeWiFi() -> Bool {
        // iOS 14+: Use NEHotspotNetwork if available
        var ssid: String?

        // CNCopyCurrentNetworkInfo is deprecated but still works and doesn't require
        // the NEHotspotConfiguration entitlement that NEHotspotNetwork needs.
        if let interfaces = CNCopySupportedInterfaces() as? [String],
           let first = interfaces.first,
           let info = CNCopyCurrentNetworkInfo(first as CFString) as? [String: Any] {
            ssid = info[kCNNetworkInfoKeySSID as String] as? String
        }

        let isHome = ssid == homeSSID
        if isHome {
            debugPrint("[WiFiUpload] Connected to \(homeSSID)")
        }
        return isHome
    }

    private func resolveVideoURL(for game: Game) -> URL? {
        guard let url = game.videoURL else { return nil }
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let filename = url.lastPathComponent
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let newURL = docs.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: newURL.path) { return newURL }
        return nil
    }
}
