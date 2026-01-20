//
//  AuthService.swift
//  SahilStatsLite
//
//  Firebase Authentication service with Sign in with Apple
//

import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import Combine

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: User?
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    private init() {
        setupAuthStateListener()
    }

    // MARK: - Auth State Listener

    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isSignedIn = user != nil
                debugPrint("[AuthService] Auth state changed: \(user?.email ?? "signed out")")
            }
        }
    }

    // MARK: - Sign In with Apple (Recommended for iOS)

    func handleSignInWithAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(nonce)
    }

    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        error = nil

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8),
                  let nonce = currentNonce else {
                error = "Failed to get Apple ID credentials"
                isLoading = false
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            do {
                let result = try await Auth.auth().signIn(with: credential)
                debugPrint("[AuthService] Signed in with Apple: \(result.user.email ?? "no email")")
            } catch {
                self.error = error.localizedDescription
                debugPrint("[AuthService] Apple sign-in error: \(error)")
            }

        case .failure(let error):
            // User cancelled is not an error we need to show
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                self.error = error.localizedDescription
            }
            debugPrint("[AuthService] Apple sign-in failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            debugPrint("[AuthService] Signed out")
        } catch {
            self.error = error.localizedDescription
            debugPrint("[AuthService] Sign out error: \(error)")
        }
    }

    // MARK: - Helper Functions

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }

    // MARK: - User Info

    var userEmail: String? {
        currentUser?.email
    }

    var userId: String? {
        currentUser?.uid
    }

    var displayName: String? {
        currentUser?.displayName
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}
