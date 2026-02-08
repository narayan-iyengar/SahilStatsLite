//
//  YouTubeService.swift
//  SahilStatsLite
//
//  PURPOSE: Lean YouTube upload service. Google Sign-In for OAuth, Keychain for
//           token storage, immediate upload over 5G (no WiFi queue). Auto-uploads
//           game videos as public to Sahil's YouTube channel.
//  KEY TYPES: YouTubeService (singleton, @MainActor)
//  DEPENDS ON: GoogleSignIn, Security (Keychain)
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import Security
import GoogleSignIn
import Combine

@MainActor
class YouTubeService: NSObject, ObservableObject {
    static let shared = YouTubeService()

    // State
    @Published var isAuthorized: Bool = false
    @Published var isUploading: Bool = false
    @Published var uploadProgress: Double = 0
    @Published var lastError: String?
    @Published var currentUploadingGameID: String?
    
    // Callback for completion (GameID, Success)
    var onUploadCompleted: ((String, Bool) -> Void)?

    private let keychainService = "com.narayan.SahilStats.youtube"
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"
    private let tokenTimestampKey = "tokenTimestamp"
    
    // Background Session
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.narayan.SahilStats.youtube.upload")
        config.isDiscretionary = false // Start immediately
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // Track current upload task ID to match delegate callbacks
    private var currentTaskID: Int?

    private override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        isAuthorized = getKeychainValue(key: accessTokenKey) != nil
    }

    func authorize() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw YouTubeError.noViewController
        }

        let scopes = ["https://www.googleapis.com/auth/youtube.upload"]

        // Use existing Google Sign-In user if available
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            let grantedScopes = currentUser.grantedScopes ?? []
            if scopes.allSatisfy({ grantedScopes.contains($0) }) {
                // Already have YouTube scope
                try saveTokens(
                    accessToken: currentUser.accessToken.tokenString,
                    refreshToken: currentUser.refreshToken.tokenString
                )
                isAuthorized = true
                return
            }
        }

        // Request sign-in with YouTube scope
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: GIDSignIn.sharedInstance.currentUser?.profile?.email,
            additionalScopes: scopes
        )

        try saveTokens(
            accessToken: result.user.accessToken.tokenString,
            refreshToken: result.user.refreshToken.tokenString
        )
        isAuthorized = true
    }

    func revokeAccess() {
        deleteKeychainValue(key: accessTokenKey)
        deleteKeychainValue(key: refreshTokenKey)
        deleteKeychainValue(key: tokenTimestampKey)
        isAuthorized = false
    }

    // MARK: - Upload

    func uploadVideo(url: URL, title: String, description: String, gameID: String) async {
        guard isAuthorized else {
            debugPrint("📺 YouTube upload skipped (not authorized)")
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            debugPrint("📺 Video file not found: \(url.path)")
            lastError = "Video file not found"
            return
        }

        isUploading = true
        currentUploadingGameID = gameID
        uploadProgress = 0
        lastError = nil

        do {
            let accessToken = try await getFreshAccessToken()
            
            // Step 1: Initialize Resumable Upload (Foreground - fast)
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
            let uploadURL = try await initializeUpload(title: title, description: description, accessToken: accessToken, fileSize: fileSize)
            
            // Step 2: Start Background Upload
            startBackgroundUpload(fileURL: url, uploadURL: uploadURL)
            
        } catch {
            debugPrint("📺 Upload failed to start: \(error.localizedDescription)")
            lastError = error.localizedDescription
            isUploading = false
            currentUploadingGameID = nil
        }
    }

    func cancelUpload() {
        guard let taskID = currentTaskID else { return }
        backgroundSession.getAllTasks { tasks in
            if let task = tasks.first(where: { $0.taskIdentifier == taskID }) {
                task.cancel()
                debugPrint("📺 Upload cancelled by user")
            }
        }
        Task { @MainActor in
            isUploading = false
            currentUploadingGameID = nil
            uploadProgress = 0
        }
    }

    private func initializeUpload(title: String, description: String, accessToken: String, fileSize: Int) async throws -> URL {
        let metadata: [String: Any] = [
            "snippet": [
                "title": title,
                "description": description,
                "categoryId": "17" // Sports
            ],
            "status": [
                "privacyStatus": "public"
            ]
        ]

        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        request.httpBody = metadataJSON

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              let location = httpResponse.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else {
            throw YouTubeError.uploadFailed("Failed to get upload URL")
        }
        
        return uploadURL
    }
    
    private func startBackgroundUpload(fileURL: URL, uploadURL: URL) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("video/*", forHTTPHeaderField: "Content-Type")
        
        let task = backgroundSession.uploadTask(with: request, fromFile: fileURL)
        currentTaskID = task.taskIdentifier
        task.resume()
        debugPrint("📺 Background upload task started (ID: \(task.taskIdentifier))")
    }

    private func performUpload(url videoURL: URL, title: String, description: String) async throws -> String {
        // Legacy method - replaced by background flow
        return ""
    }

    // MARK: - Token Management

    private func getFreshAccessToken() async throws -> String {
        guard let accessToken = getKeychainValue(key: accessTokenKey) else {
            throw YouTubeError.notAuthorized
        }

        // Check if token is old (>45 minutes)
        if let timestampStr = getKeychainValue(key: tokenTimestampKey),
           let timestamp = Double(timestampStr) {
            let tokenAge = Date().timeIntervalSince1970 - timestamp
            if tokenAge > 45 * 60 {
                // Refresh token
                return try await refreshAccessToken()
            }
        }

        return accessToken
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = getKeychainValue(key: refreshTokenKey) else {
            throw YouTubeError.notAuthorized
        }

        guard let clientId = getClientId() else {
            throw YouTubeError.invalidConfiguration
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientId)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeError.tokenRefreshFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let newAccessToken = json?["access_token"] as? String else {
            throw YouTubeError.tokenRefreshFailed
        }

        // Save new token
        setKeychainValue(key: accessTokenKey, value: newAccessToken)
        setKeychainValue(key: tokenTimestampKey, value: String(Date().timeIntervalSince1970))

        return newAccessToken
    }

    private func saveTokens(accessToken: String, refreshToken: String) throws {
        setKeychainValue(key: accessTokenKey, value: accessToken)
        setKeychainValue(key: refreshTokenKey, value: refreshToken)
        setKeychainValue(key: tokenTimestampKey, value: String(Date().timeIntervalSince1970))
    }

    private func getClientId() -> String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            return nil
        }
        return clientId
    }

    // MARK: - Keychain Helpers

    private func setKeychainValue(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = data

        SecItemAdd(newQuery as CFDictionary, nil)
    }

    private func getKeychainValue(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteKeychainValue(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - URLSessionTaskDelegate

extension YouTubeService: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in
            self.uploadProgress = progress
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            let gameID = self.currentUploadingGameID
            self.isUploading = false
            self.currentUploadingGameID = nil
            
            if let error = error {
                debugPrint("📺 Background upload failed: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
                if let id = gameID {
                    self.onUploadCompleted?(id, false)
                }
            } else {
                debugPrint("📺 Background upload completed successfully")
                self.uploadProgress = 1.0
                if let id = gameID {
                    self.onUploadCompleted?(id, true)
                }
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Parse response to get Video ID
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let videoId = json["id"] as? String {
            debugPrint("📺 YouTube Video ID: \(videoId)")
            // TODO: Update game status with video ID
        }
    }
    
    // Required for background sessions
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            // Call completion handler if stored from AppDelegate
        }
    }
}

// MARK: - Errors

enum YouTubeError: LocalizedError {
    case noViewController
    case notAuthorized
    case invalidConfiguration
    case tokenRefreshFailed
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noViewController:
            return "Unable to present authorization screen"
        case .notAuthorized:
            return "Not authorized for YouTube upload"
        case .invalidConfiguration:
            return "YouTube API not configured"
        case .tokenRefreshFailed:
            return "Failed to refresh YouTube token"
        case .uploadFailed(let message):
            return message
        }
    }
}
