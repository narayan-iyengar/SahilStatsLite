//
//  YouTubeService.swift
//  SahilStatsLite
//
//  Lean YouTube upload - no WiFi monitoring, no queue, just upload
//

import Foundation
import Security
import GoogleSignIn
import Combine

@MainActor
class YouTubeService: ObservableObject {
    static let shared = YouTubeService()

    // State
    @Published var isAuthorized: Bool = false
    @Published var isUploading: Bool = false
    @Published var uploadProgress: Double = 0
    @Published var lastError: String?

    // Settings
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "youtubeUploadEnabled")
        }
    }

    private let keychainService = "com.narayan.SahilStats.youtube"
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"
    private let tokenTimestampKey = "tokenTimestamp"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "youtubeUploadEnabled")
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

    func uploadVideo(url: URL, title: String, description: String) async -> String? {
        guard isEnabled && isAuthorized else {
            debugPrint("📺 YouTube upload skipped (enabled: \(isEnabled), authorized: \(isAuthorized))")
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            debugPrint("📺 Video file not found: \(url.path)")
            lastError = "Video file not found"
            return nil
        }

        isUploading = true
        uploadProgress = 0
        lastError = nil

        defer {
            isUploading = false
            uploadProgress = 0
        }

        // Retry up to 3 times
        for attempt in 1...3 {
            do {
                let videoId = try await performUpload(url: url, title: title, description: description)
                debugPrint("📺 YouTube upload success: \(videoId)")
                return videoId
            } catch {
                debugPrint("📺 Upload attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt == 3 {
                    lastError = error.localizedDescription
                } else {
                    // Wait before retry
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }

        return nil
    }

    private func performUpload(url videoURL: URL, title: String, description: String) async throws -> String {
        let accessToken = try await getFreshAccessToken()

        uploadProgress = 0.1

        // Get file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as! Int
        debugPrint("📺 Video size: \(fileSize / 1_000_000) MB")

        // Create resumable upload session
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

        var initRequest = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        initRequest.httpMethod = "POST"
        initRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        initRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initRequest.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        initRequest.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        initRequest.httpBody = metadataJSON

        uploadProgress = 0.2

        let (_, initResponse) = try await URLSession.shared.data(for: initRequest)

        guard let httpResponse = initResponse as? HTTPURLResponse,
              let uploadURL = httpResponse.value(forHTTPHeaderField: "Location") else {
            throw YouTubeError.uploadFailed("Failed to get upload URL (status: \((initResponse as? HTTPURLResponse)?.statusCode ?? 0))")
        }

        uploadProgress = 0.3

        // Upload the video file
        var uploadRequest = URLRequest(url: URL(string: uploadURL)!)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("video/*", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: uploadRequest, fromFile: videoURL)

        uploadProgress = 0.9

        guard let uploadResponse = response as? HTTPURLResponse, uploadResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw YouTubeError.uploadFailed("Upload failed (status: \(statusCode))")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let videoId = json?["id"] as? String else {
            throw YouTubeError.uploadFailed("No video ID in response")
        }

        uploadProgress = 1.0
        return videoId
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
