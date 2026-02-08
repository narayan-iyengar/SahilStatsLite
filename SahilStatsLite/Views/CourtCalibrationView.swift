//
//  CourtCalibrationView.swift
//  SahilStatsLite
//
//  PURPOSE: AR-style court calibration. Allows user to drag 4 corners to match
//           the court boundaries on the camera feed. Defines the "Force Field"
//           for Skynet tracking.
//  KEY TYPES: CourtCalibrationView
//  DEPENDS ON: RecordingManager, HomographyUtils, GamePersistenceManager
//

import SwiftUI
import Combine

struct CourtCalibrationView: View {
    @ObservedObject private var recordingManager = RecordingManager.shared
    @Binding var isPresented: Bool
    
    // Watch Connectivity
    private let watchService = WatchConnectivityService.shared
    
    // Cancellables for Combine
    @State private var cancellables = Set<AnyCancellable>()
    
    // Normalized coordinates (0.0 - 1.0)
    @State private var topLeft: CGPoint = CGPoint(x: 0.1, y: 0.2)
    @State private var topRight: CGPoint = CGPoint(x: 0.9, y: 0.2)
    @State private var bottomRight: CGPoint = CGPoint(x: 0.95, y: 0.9)
    @State private var bottomLeft: CGPoint = CGPoint(x: 0.05, y: 0.9)
    
    @State private var activeHandle: Handle? = nil
    
    enum Handle {
        case topLeft, topRight, bottomRight, bottomLeft
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Camera Feed (Background)
                if let session = recordingManager.captureSession {
                    CameraPreviewView(session: session)
                        .ignoresSafeArea()
                        .opacity(0.8) // Dim slightly to make overlay pop
                } else {
                    Color.black.ignoresSafeArea()
                    Text("No Camera Feed").foregroundColor(.white)
                }
                
                // 2. Court Overlay (The "Force Field")
                Path { path in
                    let tl = denormalize(topLeft, in: geometry.size)
                    let tr = denormalize(topRight, in: geometry.size)
                    let br = denormalize(bottomRight, in: geometry.size)
                    let bl = denormalize(bottomLeft, in: geometry.size)
                    
                    path.move(to: tl)
                    path.addLine(to: tr)
                    path.addLine(to: br)
                    path.addLine(to: bl)
                    path.closeSubpath()
                }
                .fill(Color.green.opacity(0.2))
                .overlay(
                    Path { path in
                        let tl = denormalize(topLeft, in: geometry.size)
                        let tr = denormalize(topRight, in: geometry.size)
                        let br = denormalize(bottomRight, in: geometry.size)
                        let bl = denormalize(bottomLeft, in: geometry.size)
                        
                        path.move(to: tl)
                        path.addLine(to: tr)
                        path.addLine(to: br)
                        path.addLine(to: bl)
                        path.closeSubpath()
                    }
                    .stroke(Color.green, lineWidth: 2)
                )
                .allowsHitTesting(false) // Let touches pass through to handles
                
                // 3. Draggable Handles
                dragHandle(position: $topLeft, handle: .topLeft, in: geometry.size)
                dragHandle(position: $topRight, handle: .topRight, in: geometry.size)
                dragHandle(position: $bottomRight, handle: .bottomRight, in: geometry.size)
                dragHandle(position: $bottomLeft, handle: .bottomLeft, in: geometry.size)
                
                // 4. Instructions / Controls
                VStack {
                    Text("Drag corners to match court floor")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.top, 40)
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        
                        Button("Reset") {
                            resetCorners()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        
                        Button("Save Court") {
                            saveCalibration()
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            loadSavedCalibration()
            setupRemoteControl()
        }
    }
    
    // MARK: - Remote Control
    
    private func setupRemoteControl() {
        watchService.calibrationSubject
            .receive(on: DispatchQueue.main)
            .sink { command, value in
                if command == "save" {
                    saveCalibration()
                    isPresented = false
                } else if command == "selectCorner", let cornerName = value {
                    switch cornerName {
                    case "Top Left": activeHandle = .topLeft
                    case "Top Right": activeHandle = .topRight
                    case "Bottom Right": activeHandle = .bottomRight
                    case "Bottom Left": activeHandle = .bottomLeft
                    default: break
                    }
                }
            }
            .store(in: &cancellables)
        
        watchService.calibrationMoveSubject
            .receive(on: DispatchQueue.main)
            .sink { dx, dy in
                let handle = activeHandle ?? .topLeft
                
                // Scale movement (adjust sensitivity as needed)
                let moveX = CGFloat(dx) * 2.0
                let moveY = CGFloat(dy) * 2.0
                
                switch handle {
                case .topLeft:
                    topLeft.x = (topLeft.x + moveX).clamped(to: 0...1)
                    topLeft.y = (topLeft.y + moveY).clamped(to: 0...1)
                case .topRight:
                    topRight.x = (topRight.x + moveX).clamped(to: 0...1)
                    topRight.y = (topRight.y + moveY).clamped(to: 0...1)
                case .bottomRight:
                    bottomRight.x = (bottomRight.x + moveX).clamped(to: 0...1)
                    bottomRight.y = (bottomRight.y + moveY).clamped(to: 0...1)
                case .bottomLeft:
                    bottomLeft.x = (bottomLeft.x + moveX).clamped(to: 0...1)
                    bottomLeft.y = (bottomLeft.y + moveY).clamped(to: 0...1)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Helper Views
    
    private func dragHandle(position: Binding<CGPoint>, handle: Handle, in size: CGSize) -> some View {
        let pixelPos = denormalize(position.wrappedValue, in: size)
        
        return Circle()
            .fill(Color.white)
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .overlay(
                Circle()
                    .stroke(activeHandle == handle ? Color.orange : Color.green, lineWidth: 3)
            )
            .position(pixelPos)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        activeHandle = handle
                        let newPos = CGPoint(
                            x: value.location.x / size.width,
                            y: value.location.y / size.height
                        )
                        // Clamp to valid range
                        position.wrappedValue = CGPoint(
                            x: max(0, min(1, newPos.x)),
                            y: max(0, min(1, newPos.y))
                        )
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
    }
    
    // MARK: - Logic
    
    private func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
    
    private func resetCorners() {
        withAnimation {
            topLeft = CGPoint(x: 0.1, y: 0.2)
            topRight = CGPoint(x: 0.9, y: 0.2)
            bottomRight = CGPoint(x: 0.95, y: 0.9)
            bottomLeft = CGPoint(x: 0.05, y: 0.9)
        }
    }
    
    private func saveCalibration() {
        let geometry = CourtGeometry(
            topLeft: topLeft,
            topRight: topRight,
            bottomRight: bottomRight,
            bottomLeft: bottomLeft
        )
        
        if let data = try? JSONEncoder().encode(geometry) {
            UserDefaults.standard.set(data, forKey: "savedCourtGeometry")
            debugPrint("✅ Court geometry saved")
            
            // Notify Skynet immediately
            AutoZoomManager.shared.updateCourtGeometry(geometry)
        }
    }
    
    private func loadSavedCalibration() {
        if let data = UserDefaults.standard.data(forKey: "savedCourtGeometry"),
           let geometry = try? JSONDecoder().decode(CourtGeometry.self, from: data) {
            topLeft = geometry.topLeft
            topRight = geometry.topRight
            bottomRight = geometry.bottomRight
            bottomLeft = geometry.bottomLeft
        }
    }
}

#Preview {
    CourtCalibrationView(isPresented: .constant(true))
}
