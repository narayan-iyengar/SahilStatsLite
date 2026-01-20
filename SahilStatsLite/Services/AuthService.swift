//
//  AuthService.swift
//  SahilStatsLite
//
//  Firebase Authentication service with Google Sign-In
//

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Combine

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: User?
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var isLoading: Bool = true
    @Published var error: String?

    private var authStateListener: AuthStateDidChangeListenerHandle?

    private init() {
        setupGoogleSignIn()
        setupAuthStateListener()
    }

    // MARK: - Setup

    private func setupGoogleSignIn() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            debugPrint("[AuthService] Error: Could not find GoogleService-Info.plist or CLIENT_ID")
            return
        }

        guard FirebaseApp.app() != nil else {
            debugPrint("[AuthService] Error: Firebase not configured")
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        debugPrint("[AuthService] Google Sign-In configured")
    }

    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isSignedIn = user != nil && !(user?.isAnonymous ?? true)
                self?.isLoading = false
                debugPrint("[AuthService] Auth state changed: \(user?.email ?? "signed out")")
            }
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        isLoading = true
        error = nil

        // Get presenting view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let presentingViewController = window.rootViewController else {
            error = "Could not find presenting view controller"
            isLoading = false
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                error = "Failed to get ID token"
                isLoading = false
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            debugPrint("[AuthService] Signed in with Google: \(authResult.user.email ?? "no email")")

        } catch {
            // Check if user cancelled
            if (error as NSError).code == GIDSignInError.canceled.rawValue {
                debugPrint("[AuthService] Sign-in cancelled by user")
            } else {
                self.error = error.localizedDescription
                debugPrint("[AuthService] Google sign-in error: \(error)")
            }
        }

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            // Sign out from Google
            GIDSignIn.sharedInstance.signOut()

            // Sign out from Firebase
            try Auth.auth().signOut()

            debugPrint("[AuthService] Signed out")
        } catch {
            self.error = error.localizedDescription
            debugPrint("[AuthService] Sign out error: \(error)")
        }
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
