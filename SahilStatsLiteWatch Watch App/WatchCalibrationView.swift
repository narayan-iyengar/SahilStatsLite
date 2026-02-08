//
//  WatchCalibrationView.swift
//  SahilStatsLiteWatch
//
//  PURPOSE: Remote control for AR Court Calibration. Allows adjusting court
//           corners when phone is mounted high on a tripod.
//           Sends d-pad commands to iPhone.
//  KEY TYPES: WatchCalibrationView
//  DEPENDS ON: WatchConnectivityClient
//

import SwiftUI
import WatchKit

struct WatchCalibrationView: View {
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCorner: String = "Top Left"
    @State private var corners = ["Top Left", "Top Right", "Bottom Right", "Bottom Left"]
    @State private var cornerIndex = 0
    
    // Sensitivity for Digital Crown
    @State private var crownValue: Double = 0.0
    
    var body: some View {
        VStack(spacing: 8) {
            // Header: Selected Corner
            HStack {
                Button {
                    cycleCorner(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                
                Text(selectedCorner)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)
                    .frame(minWidth: 80)
                
                Button {
                    cycleCorner(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            
            // D-Pad Grid
            VStack(spacing: 4) {
                Button {
                    move(dx: 0, dy: -0.01) // Up
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 20))
                        .frame(width: 40, height: 30)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 16) {
                    Button {
                        move(dx: -0.01, dy: 0) // Left
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .frame(width: 40, height: 30)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        move(dx: 0.01, dy: 0) // Right
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20))
                            .frame(width: 40, height: 30)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    move(dx: 0, dy: 0.01) // Down
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20))
                        .frame(width: 40, height: 30)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button("Save") {
                    connectivity.sendCalibrationCommand("save")
                    dismiss()
                }
                .tint(.green)
                .font(.system(size: 14))
            }
        }
        .onAppear {
            connectivity.sendCalibrationCommand("open")
        }
        .focusable()
        .digitalCrownRotation($crownValue, from: -100, through: 100, by: 0.1, sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crownValue) { oldValue, newValue in
            // Use Crown for fine-tuning Y axis? Or scale?
            // For now let's just stick to buttons for simplicity
        }
    }
    
    private func cycleCorner(_ direction: Int) {
        cornerIndex = (cornerIndex + direction + corners.count) % corners.count
        selectedCorner = corners[cornerIndex]
        
        // Notify phone which corner is active
        connectivity.sendCalibrationCommand("selectCorner", value: selectedCorner)
        WKInterfaceDevice.current().play(.click)
    }
    
    private func move(dx: Double, dy: Double) {
        connectivity.sendCalibrationMove(dx: dx, dy: dy)
        WKInterfaceDevice.current().play(.click)
    }
}

#Preview {
    WatchCalibrationView()
        .environmentObject(WatchConnectivityClient.shared)
}
