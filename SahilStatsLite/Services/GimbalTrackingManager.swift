//
//  GimbalTrackingManager.swift
//  SahilStatsLite
//
//  PURPOSE: DockKit gimbal integration for Insta360 Flow Pro 2. Controls
//           physical pan/tilt as a 2-axis stabilizer guided by Skynet.
//           DockKit system tracking AI is DISABLED. Skynet is the sole tracking brain.
//           Skynet calls updateTrackingROI(center:) each frame to steer the physical gimbal.
//  KEY TYPES: GimbalTrackingManager (singleton), GimbalMode (off/stabilize/track)
//  DEPENDS ON: DockKit (iOS 18+), AVFoundation
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI
import Spatial
#if canImport(DockKit)
import DockKit
#endif

// MARK: - Gimbal Mode

enum GimbalMode: String, CaseIterable {
    case off = "Off"
    case stabilize = "Stabilize"
    case track = "Auto-Track"

    var icon: String {
        switch self {
        case .off: return "iphone"
        case .stabilize: return "gyroscope"
        case .track: return "person.fill.viewfinder"
        }
    }

    var description: String {
        switch self {
        case .off: return "Handheld, no gimbal"
        case .stabilize: return "Gimbal smoothing, manual aim"
        case .track: return "Auto-follow subjects"
        }
    }
}

@MainActor
final class GimbalTrackingManager: ObservableObject {
    static let shared = GimbalTrackingManager()

    // MARK: - Published Properties

    @Published var gimbalMode: GimbalMode = .track
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
    private var roiUpdateTask: Task<Void, Never>?

    // MARK: - PID Controller State (pan-only)

    // Proportional gain: how aggressively the gimbal responds to subject offset.
    // error = actionCenter.x - 0.5 (range ±0.5). At max error, gimbal pans at maxPanVelocity.
    // Tune Kp up if tracking feels sluggish, down if it overshoots.
    private let Kp: Double = 1.6

    // Maximum pan velocity in radians/second sent to DockKit.
    // 0.8 rad/s ≈ 46°/s — fast enough for fast breaks, smooth enough for broadcast feel.
    private let maxPanVelocity: Double = 0.8

    // Deadband: don't command any velocity if subject is within 3% of frame center.
    // Prevents the gimbal from nervously hunting around dead center.
    private let panDeadband: CGFloat = 0.03

    private var lastActionCenterX: CGFloat = 0.5

    // MARK: - Initialization

    private init() {
        checkDockKitAvailability()
    }

    // MARK: - DockKit Availability

    private func checkDockKitAvailability() {
        #if canImport(DockKit)
        if #available(iOS 18.0, *) {
            debugPrint("[DockKit] iOS 18+ detected, starting accessory scan...")
            Task {
                do {
                    let manager = DockAccessoryManager.shared
                    debugPrint("[DockKit] Got DockAccessoryManager, waiting for accessoryStateChanges...")
                    let stateChanges = try manager.accessoryStateChanges

                    for await stateChange in stateChanges {
                        debugPrint("[DockKit] State change received!")
                        if let accessory = stateChange.accessory {
                            // Immediately disable Insta360's own tracking AI the moment the
                            // gimbal connects. This is the DockKit equivalent of Lock mode —
                            // the gimbal stabilizes but does not track on its own.
                            // Skynet will steer it via updateTrackingROI(center:).
                            try? await manager.setSystemTrackingEnabled(false)
                            debugPrint("[DockKit] ✅ Gimbal connected: \(accessory.identifier.name) — Lock mode engaged")
                            await MainActor.run {
                                self.dockAccessory = accessory
                                self.isDockKitAvailable = true
                            }
                        } else {
                            await MainActor.run {
                                self.dockAccessory = nil
                                self.isDockKitAvailable = false
                                debugPrint("[DockKit] ❌ Gimbal disconnected")
                            }
                        }
                    }
                } catch {
                    debugPrint("[DockKit] ❌ Error: \(error.localizedDescription)")
                    await MainActor.run {
                        self.isDockKitAvailable = false
                        self.lastError = error.localizedDescription
                    }
                }
            }
        } else {
            debugPrint("[DockKit] ❌ iOS version < 18, DockKit not available")
            isDockKitAvailable = false
        }
        #else
        debugPrint("[DockKit] ❌ DockKit framework not available (not imported)")
        isDockKitAvailable = false
        #endif
    }

    // MARK: - Tracking Control

    func startTracking() {
        // If mode is off, don't do anything
        guard gimbalMode != .off else {
            debugPrint("[Gimbal] Mode is OFF, skipping gimbal")
            return
        }

        #if canImport(DockKit)
        guard let _ = dockAccessory else {
            lastError = "No gimbal connected"
            return
        }

        if #available(iOS 18.0, *) {
            isTrackingActive = true
            lastError = nil
            lastROICenter = CGPoint(x: 0.5, y: 0.5)

            Task {
                do {
                    let manager = DockAccessoryManager.shared
                    // CRITICAL: Disable DockKit's own tracking AI entirely.
                    // The Insta360 Flow Pro 2 is used as a pure 2-axis physical stabilizer.
                    // Skynet (AutoZoomManager) is the sole tracking brain. It calls
                    // updateTrackingROI(center:) each frame to steer where the gimbal points.
                    try await manager.setSystemTrackingEnabled(false)
                    debugPrint("[Gimbal] System tracking DISABLED — Skynet is in command")
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

        trackingTask?.cancel()
        trackingTask = nil
        roiUpdateTask?.cancel()
        roiUpdateTask = nil

        isTrackingActive = false
        trackedSubjectCount = 0

        // Send zero velocity so the gimbal doesn't continue panning after tracking stops
        #if canImport(DockKit)
        if #available(iOS 18.0, *), let accessory = dockAccessory {
            Task { try? await accessory.setAngularVelocity(Vector3D(x: 0, y: 0, z: 0)) }
        }
        #endif
    }

    // MARK: - Skynet-Driven Physical Gimbal Steering (PID velocity control)

    /// Called by AutoZoomManager each frame with Skynet's computed action center (normalized 0–1).
    ///
    /// Uses setAngularVelocity instead of setRegionOfInterest. ROI hints tell DockKit "look here"
    /// and it interprets the request — slow, indirect, imprecise. Angular velocity is a direct
    /// motor command: error → velocity → move. Response is immediate and proportional.
    ///
    /// P controller (pan axis only):
    ///   error = actionCenter.x - 0.5   (positive = subject right of center)
    ///   panVelocity = Kp × error        (clamped to ±maxPanVelocity rad/s)
    ///   velocity = 0 when |error| < deadband  (stops the gimbal precisely at center)
    ///
    /// Axis convention (DockKit / Spatial.Vector3D for a portrait gimbal in landscape):
    ///   Y axis = yaw (left/right pan). X = pitch (tilt). Z = roll (locked, always 0).
    func updateTrackingROI(center: CGPoint) {
        guard gimbalMode == .track, isDockKitAvailable, isTrackingActive else { return }

        lastActionCenterX = center.x

        roiUpdateTask?.cancel()
        roiUpdateTask = Task {
            #if canImport(DockKit)
            if #available(iOS 18.0, *) {
                guard let accessory = dockAccessory else { return }

                // Error: how far the subject is from the frame center (range ±0.5)
                let error = Double(center.x) - 0.5

                // Within deadband — stop the gimbal so it doesn't hunt around center
                guard abs(error) > Double(panDeadband) else {
                    try? await accessory.setAngularVelocity(Vector3D(x: 0, y: 0, z: 0))
                    return
                }

                // Proportional pan velocity — clamped to safe max
                let rawVelocity = Kp * error
                let panVelocity = max(-maxPanVelocity, min(maxPanVelocity, rawVelocity))

                // Y axis = yaw (pan). X/Z locked to 0 (no tilt or roll commands).
                let velocity = Vector3D(x: 0, y: panVelocity, z: 0)
                do {
                    try await accessory.setAngularVelocity(velocity)
                    debugPrint("[Gimbal] PID pan → err:\(String(format: "%.3f", error)) vel:\(String(format: "%.2f", panVelocity)) rad/s")
                } catch {
                    debugPrint("[Gimbal] setAngularVelocity failed: \(error.localizedDescription)")
                }
            }
            #endif
        }
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
