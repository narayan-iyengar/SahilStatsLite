//
//  WatchStatsView.swift
//  SahilStatsLiteWatch
//
//  Jony Ive-inspired stats tracking: simplicity, generous touch targets, focus on the essential
//

import SwiftUI
import WatchKit

struct WatchStatsView: View {
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @State private var selectedShotType: ShotType = .twoPoint
    @State private var showOtherStats: Bool = false

    enum ShotType: String, CaseIterable {
        case twoPoint = "2PT"
        case threePoint = "3PT"
        case freeThrow = "FT"
    }

    private var points: Int {
        (connectivity.fg2Made * 2) + (connectivity.fg3Made * 3) + connectivity.ftMade
    }

    private var currentMade: Int {
        switch selectedShotType {
        case .twoPoint: return connectivity.fg2Made
        case .threePoint: return connectivity.fg3Made
        case .freeThrow: return connectivity.ftMade
        }
    }

    private var currentAtt: Int {
        switch selectedShotType {
        case .twoPoint: return connectivity.fg2Att
        case .threePoint: return connectivity.fg3Att
        case .freeThrow: return connectivity.ftAtt
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showOtherStats {
                otherStatsView
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                shootingView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showOtherStats)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -30 {
                        showOtherStats = true
                    } else if value.translation.width > 30 {
                        showOtherStats = false
                    }
                }
        )
    }

    // MARK: - Shooting View (Main)

    private var shootingView: some View {
        VStack(spacing: 0) {
            // Points header
            HStack {
                Text("\(points)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                Text("PTS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange.opacity(0.7))
                Spacer()
                Text("\(currentMade)/\(currentAtt)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Shot type selector - pill style
            HStack(spacing: 0) {
                ForEach(ShotType.allCases, id: \.self) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedShotType = type
                        }
                    } label: {
                        Text(type.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedShotType == type ? .black : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedShotType == type
                                    ? Color.white
                                    : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white.opacity(0.15))
            .cornerRadius(20)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()

            // Big make/miss buttons
            HStack(spacing: 12) {
                // MAKE button
                Button {
                    recordShot(made: true)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                        Text("MAKE")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green)
                    )
                }
                .buttonStyle(.plain)

                // MISS button
                Button {
                    recordShot(made: false)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 28, weight: .bold))
                        Text("MISS")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.red.opacity(0.85))
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(height: 80)
            .padding(.horizontal, 8)

            // Swipe hint
            HStack(spacing: 4) {
                Text("More stats")
                    .font(.system(size: 9, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.3))
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Other Stats View

    private var otherStatsView: some View {
        VStack(spacing: 8) {
            // Back hint
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .semibold))
                Text("Shooting")
                    .font(.system(size: 9, weight: .medium))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.3))
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Stats grid - 2x3 layout with big buttons
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                statTile("AST", connectivity.assists, .green) {
                    connectivity.updateStat("assists", value: 1)
                }
                statTile("REB", connectivity.rebounds, .orange) {
                    connectivity.updateStat("rebounds", value: 1)
                }
                statTile("STL", connectivity.steals, .cyan) {
                    connectivity.updateStat("steals", value: 1)
                }
                statTile("BLK", connectivity.blocks, .purple) {
                    connectivity.updateStat("blocks", value: 1)
                }
                statTile("TO", connectivity.turnovers, .red) {
                    connectivity.updateStat("turnovers", value: 1)
                }
                statTile("PF", 0, .gray) {
                    // Fouls - placeholder
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
    }

    // MARK: - Stat Tile

    private func statTile(_ label: String, _ value: Int, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func recordShot(made: Bool) {
        switch selectedShotType {
        case .twoPoint:
            if made {
                connectivity.updateStat("fg2Made", value: 1)
            }
            connectivity.updateStat("fg2Att", value: 1)
        case .threePoint:
            if made {
                connectivity.updateStat("fg3Made", value: 1)
            }
            connectivity.updateStat("fg3Att", value: 1)
        case .freeThrow:
            if made {
                connectivity.updateStat("ftMade", value: 1)
            }
            connectivity.updateStat("ftAtt", value: 1)
        }

        // Haptic feedback
        WKInterfaceDevice.current().play(.click)
    }
}

#Preview("Stats — 45mm") {
    WatchConnectivityClient.configureForPreview()
    return WatchStatsView()
        .environmentObject(WatchConnectivityClient.shared)
}

#Preview("Stats — 49mm") {
    WatchConnectivityClient.configureForPreview()
    return WatchStatsView()
        .environmentObject(WatchConnectivityClient.shared)
}
