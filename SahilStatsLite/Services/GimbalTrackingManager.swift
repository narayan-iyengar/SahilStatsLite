//
//  GimbalTrackingManager.swift
//  SahilStatsLite
//
//  DockKit integration for Insta360 Flow 2 Pro smart tracking
//  Requires: iOS 18+ with DockKit framework
//

import Foundation
import AVFoundation
import Combine
import SwiftUI
#if canImport(DockKit)
import DockKit
#endif

@MainActor
final class GimbalTrackingManager: ObservableObject {
    static let shared = GimbalTrackingManager()

    // MARK: - Published Properties

    @Published var isTrackingActive: Bool = false
    @Published var isDockKitAvailable: Bool = false
    @Published var lastError: String?
    @Published var trackedSubjectCount: Int = 0

    // MARK: - DockKit Properties

    #if canImport(DockKit)
    @available(iOS 18.0, *)
    private var dockAccessory: DockAccessory?
    #endif

    private var trackingTask: Task<Void, Never>?

    // Court region for tracking (normalized 0.0-1.0)
    private var courtRegion: CGRect {
        CGRect(x: 0.05, y: 0.15, width: 0.9, height: 0.75)
    }

    // MARK: - Initialization

    private init() {
        checkDockKitAvailability()
    }

    // MARK: - DockKit Availability

    private func checkDockKitAvailability() {
        #if canImport(DockKit)
        if #available(iOS 18.0, *) {
            Task {
                do {
                    let manager = DockAccessoryManager.shared
                    let stateChanges = try manager.accessoryStateChanges

                    for await stateChange in stateChanges {
                        await MainActor.run {
                            if let accessory = stateChange.accessory {
                                self.dockAccessory = accessory
                                self.isDockKitAvailable = true
                                debugPrint("Gimbal connected: \(accessory.identifier.name)")
                            } else {
                                self.dockAccessory = nil
                                self.isDockKitAvailable = false
                                debugPrint("No gimbal connected")
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.isDockKitAvailable = false
                        self.lastError = error.localizedDescription
                    }
                }
            }
        } else {
            isDockKitAvailable = false
        }
        #else
        isDockKitAvailable = false
        #endif
    }

    // MARK: - Tracking Control

    func startTracking() {
        #if canImport(DockKit)
        guard let _ = dockAccessory else {
            lastError = "No gimbal connected"
            return
        }

        if #available(iOS 18.0, *) {
            isTrackingActive = true
            lastError = nil

            Task {
                do {
                    guard let accessory = dockAccessory else { return }

                    // Set region of interest to court area
                    try await accessory.setRegionOfInterest(courtRegion)

                    // Enable system tracking
                    let manager = DockAccessoryManager.shared
                    try await manager.setSystemTrackingEnabled(true)

                    debugPrint("Gimbal tracking started")

                    // Monitor tracking state
                    trackingTask = Task {
                        do {
                            let trackingStates = try accessory.trackingStates

                            for try await trackingState in trackingStates {
                                await MainActor.run {
                                    self.trackedSubjectCount = trackingState.trackedSubjects.count

                                    // Auto-zoom based on subject count
                                    if self.trackedSubjectCount > 0 {
                                        let optimalZoom: CGFloat
                                        if self.trackedSubjectCount >= 5 {
                                            optimalZoom = 1.0
                                        } else if self.trackedSubjectCount <= 2 {
                                            optimalZoom = 2.0
                                        } else {
                                            optimalZoom = 1.5
                                        }

                                        let currentZoom = RecordingManager.shared.getCurrentZoom()
                                        if abs(currentZoom - optimalZoom) > 0.3 {
                                            _ = RecordingManager.shared.setZoom(factor: optimalZoom)
                                        }
                                    }
                                }
                            }
                        } catch {
                            debugPrint("Tracking state error: \(error)")
                        }
                    }

                } catch {
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                        self.isTrackingActive = false
                    }
                }
            }
        }
        #endif
    }

    func stopTracking() {
        guard isTrackingActive else { return }

        #if canImport(DockKit)
        if #available(iOS 18.0, *) {
            trackingTask?.cancel()
            trackingTask = nil

            Task {
                do {
                    let manager = DockAccessoryManager.shared
                    try await manager.setSystemTrackingEnabled(false)
                } catch {
                    debugPrint("Error stopping tracking: \(error)")
                }

                await MainActor.run {
                    self.isTrackingActive = false
                    self.trackedSubjectCount = 0
                }
            }
        } else {
            isTrackingActive = false
        }
        #else
        isTrackingActive = false
        #endif
    }

    // MARK: - Status

    func getStatusText() -> String {
        if !isDockKitAvailable {
            return "No gimbal"
        }
        if isTrackingActive {
            return trackedSubjectCount > 0 ? "Tracking \(trackedSubjectCount)" : "Tracking"
        }
        return "Ready"
    }
}
