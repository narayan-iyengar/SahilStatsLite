//
//  WatchStatsView.swift
//  SahilStatsLiteWatch
//
//  Stats tracking screen - shooting stats with make/miss, other stats with tap to increment
//

import SwiftUI

struct WatchStatsView: View {
    @EnvironmentObject var connectivity: WatchConnectivityClient

    private var points: Int {
        (connectivity.fg2Made * 2) + (connectivity.fg3Made * 3) + connectivity.ftMade
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                // Header
                VStack(spacing: 2) {
                    Text(connectivity.teamName.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("\(points) pts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.bottom, 4)

                // Shooting stats
                HStack(spacing: 4) {
                    shootingStat(label: "2PT", made: connectivity.fg2Made, att: connectivity.fg2Att) { made in
                        if made {
                            connectivity.updateStat("fg2Made", value: 1)
                            connectivity.updateStat("fg2Att", value: 1)
                        } else {
                            connectivity.updateStat("fg2Att", value: 1)
                        }
                    }
                    shootingStat(label: "3PT", made: connectivity.fg3Made, att: connectivity.fg3Att) { made in
                        if made {
                            connectivity.updateStat("fg3Made", value: 1)
                            connectivity.updateStat("fg3Att", value: 1)
                        } else {
                            connectivity.updateStat("fg3Att", value: 1)
                        }
                    }
                    shootingStat(label: "FT", made: connectivity.ftMade, att: connectivity.ftAtt) { made in
                        if made {
                            connectivity.updateStat("ftMade", value: 1)
                            connectivity.updateStat("ftAtt", value: 1)
                        } else {
                            connectivity.updateStat("ftAtt", value: 1)
                        }
                    }
                }

                // Other stats
                HStack(spacing: 3) {
                    statButton(label: "AST", value: connectivity.assists) {
                        connectivity.updateStat("assists", value: 1)
                    }
                    statButton(label: "REB", value: connectivity.rebounds) {
                        connectivity.updateStat("rebounds", value: 1)
                    }
                    statButton(label: "STL", value: connectivity.steals) {
                        connectivity.updateStat("steals", value: 1)
                    }
                    statButton(label: "BLK", value: connectivity.blocks) {
                        connectivity.updateStat("blocks", value: 1)
                    }
                    statButton(label: "TO", value: connectivity.turnovers) {
                        connectivity.updateStat("turnovers", value: 1)
                    }
                }

                // Back hint
                Text("\u{2193} Score")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Shooting Stat Tile

    private func shootingStat(label: String, made: Int, att: Int, onTap: @escaping (Bool) -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 6) {
                // Make button
                Button {
                    onTap(true)
                } label: {
                    Text("\u{2713}")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Miss button
                Button {
                    onTap(false)
                } label: {
                    Text("\u{2717}")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Text("\(made)/\(att)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Stat Button

    private func statButton(label: String, value: Int, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text(label)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WatchStatsView()
        .environmentObject(WatchConnectivityClient.shared)
}
