//
//  EditGameView.swift
//  SahilStatsLite
//
//  PURPOSE: Edit post-game stats and scores. "Jony Ive" style: interactive
//           tiles instead of a boring form. Tap to increment, long press to decrement.
//  KEY TYPES: EditGameView
//  DEPENDS ON: Game, GamePersistenceManager
//

import SwiftUI

struct EditGameView: View {
    @Binding var game: Game
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    
    // Local state for editing
    @State private var editedGame: Game
    
    init(game: Binding<Game>) {
        self._game = game
        self._editedGame = State(initialValue: game.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header (Score)
                    scoreEditor
                    
                    // Player Stats
                    playerStatsEditor
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private func saveChanges() {
        // Update the bound game (updates UI immediately)
        game = editedGame
        
        // Persist changes
        persistenceManager.saveGame(editedGame)
        
        dismiss()
    }
    
    // MARK: - Score Editor
    
    private var scoreEditor: some View {
        VStack(spacing: 16) {
            Text("Game Score")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                // Home Team
                scoreTile(
                    name: editedGame.teamName,
                    score: $editedGame.myScore,
                    color: .orange
                )
                
                // Opponent
                scoreTile(
                    name: editedGame.opponent,
                    score: $editedGame.opponentScore,
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private func scoreTile(name: String, score: Binding<Int>, color: Color) -> some View {
        VStack(spacing: 12) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack(spacing: 16) {
                Button {
                    if score.wrappedValue > 0 { score.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color(.systemGray4))
                }
                .buttonStyle(.plain)
                
                Text("\(score.wrappedValue)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .frame(minWidth: 50)
                
                Button {
                    score.wrappedValue += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(color)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Player Stats Editor
    
    private var playerStatsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sahil's Stats")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                // Shooting
                VStack(spacing: 12) {
                    Text("Shooting (Made / Attempts)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    shootingRow(label: "2PT", made: $editedGame.playerStats.fg2Made, att: $editedGame.playerStats.fg2Attempted, color: .blue)
                    shootingRow(label: "3PT", made: $editedGame.playerStats.fg3Made, att: $editedGame.playerStats.fg3Attempted, color: .purple)
                    shootingRow(label: "FT", made: $editedGame.playerStats.ftMade, att: $editedGame.playerStats.ftAttempted, color: .cyan)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                // Other Stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statEditor(label: "AST", value: $editedGame.playerStats.assists, color: .green)
                    statEditor(label: "REB", value: $editedGame.playerStats.rebounds, color: .orange)
                    statEditor(label: "STL", value: $editedGame.playerStats.steals, color: .teal)
                    statEditor(label: "BLK", value: $editedGame.playerStats.blocks, color: .indigo)
                    statEditor(label: "TO", value: $editedGame.playerStats.turnovers, color: .red)
                    statEditor(label: "PF", value: $editedGame.playerStats.fouls, color: .gray)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private func shootingRow(label: String, made: Binding<Int>, att: Binding<Int>, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 40, alignment: .leading)
            
            Spacer()
            
            // Made
            HStack(spacing: 12) {
                Button { if made.wrappedValue > 0 { made.wrappedValue -= 1 } } label: {
                    Image(systemName: "minus")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Text("\(made.wrappedValue)")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 20)
                
                Button { made.wrappedValue += 1; if made.wrappedValue > att.wrappedValue { att.wrappedValue = made.wrappedValue } } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            
            Text("/")
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            // Attempts
            HStack(spacing: 12) {
                Button { if att.wrappedValue > made.wrappedValue { att.wrappedValue -= 1 } } label: {
                    Image(systemName: "minus")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Text("\(att.wrappedValue)")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 20)
                
                Button { att.wrappedValue += 1 } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func statEditor(label: String, value: Binding<Int>, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text("\(value.wrappedValue)")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                Button { if value.wrappedValue > 0 { value.wrappedValue -= 1 } } label: {
                    Image(systemName: "minus")
                        .font(.caption2)
                        .frame(width: 24, height: 24)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button { value.wrappedValue += 1 } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .frame(width: 24, height: 24)
                        .background(color.opacity(0.2))
                        .foregroundColor(color)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
