//
//  AuthView.swift
//  SahilStatsLite
//
//  Sign-in view for Firebase authentication
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // App icon and title
                VStack(spacing: 16) {
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.orange)

                    Text("SahilStats")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Sign in to sync your games across devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Sign-in options
                VStack(spacing: 16) {
                    if authService.isSignedIn {
                        // Already signed in
                        signedInView
                    } else {
                        // Sign in with Apple
                        SignInWithAppleButton(
                            onRequest: { request in
                                authService.handleSignInWithAppleRequest(request)
                            },
                            onCompletion: { result in
                                Task {
                                    await authService.handleSignInWithAppleCompletion(result)
                                }
                            }
                        )
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .cornerRadius(10)
                        .padding(.horizontal, 32)

                        // Continue without signing in
                        Button {
                            dismiss()
                        } label: {
                            Text("Continue without signing in")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }

                // Error display
                if let error = authService.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Loading indicator
                if authService.isLoading {
                    ProgressView()
                        .padding()
                }

                Spacer()

                // Privacy note
                Text("Your data is stored securely in Firebase")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Signed In View

    private var signedInView: some View {
        VStack(spacing: 20) {
            // User info
            VStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text("Signed In")
                    .font(.headline)
                    .foregroundStyle(.green)

                if let email = authService.userEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Sync status
            HStack(spacing: 8) {
                if persistenceManager.isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing...")
                } else if let lastSync = persistenceManager.lastSyncTime {
                    Image(systemName: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                    Text("Last synced: \(lastSync.formatted(date: .omitted, time: .shortened))")
                } else {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.blue)
                    Text("Connected to cloud")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Sync error
            if let syncError = persistenceManager.syncError {
                Text(syncError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Actions
            VStack(spacing: 12) {
                // Force sync button
                Button {
                    Task {
                        await persistenceManager.forceSyncFromFirebase()
                    }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(persistenceManager.isSyncing)

                // Sign out button
                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
        }
    }
}

// MARK: - Profile Button (for HomeView)

struct ProfileButton: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @State private var showAuthView = false

    var body: some View {
        Button {
            showAuthView = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: authService.isSignedIn ? "person.circle.fill" : "person.circle")
                    .font(.title2)
                    .foregroundStyle(authService.isSignedIn ? .green : .secondary)

                // Sync indicator
                if authService.isSignedIn {
                    if persistenceManager.isSyncing {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                    } else if persistenceManager.syncError != nil {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .sheet(isPresented: $showAuthView) {
            AuthView()
        }
    }
}

#Preview {
    AuthView()
}
