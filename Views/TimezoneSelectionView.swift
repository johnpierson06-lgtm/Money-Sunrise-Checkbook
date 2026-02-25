//
//  TimezoneSelectionView.swift
//  CheckbookApp
//
//  View for selecting the Money file's timezone on first open
//

import SwiftUI

struct TimezoneSelectionView: View {
    let onTimezoneSelected: () -> Void
    
    @State private var selectedTimezone: TimezoneManager.StandardTimezone?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .padding(.top, 20)
                    
                    Text("Select Your Timezone")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("What timezone was your Money file created in?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Info Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        
                        Text("Why do we need this?")
                            .font(.headline)
                    }
                    
                    Text("Microsoft Money stores dates in a specific timezone. We need to know which timezone your file uses to display and save dates correctly.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("💡 This is usually the timezone where you created the Money file.")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Timezone List
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Timezone")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List(TimezoneManager.standardTimezones) { timezone in
                        Button {
                            selectedTimezone = timezone
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(timezone.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Text(timezone.abbreviation)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("UTC\(timezone.offsetHours >= 0 ? "+" : "")\(timezone.offsetHours)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                                
                                if selectedTimezone?.id == timezone.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
                
                Spacer()
                
                // Continue Button
                Button {
                    saveAndContinue()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedTimezone != nil ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(selectedTimezone == nil)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("First Time Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func saveAndContinue() {
        guard let timezone = selectedTimezone else { return }
        
        // Save the timezone offset
        TimezoneManager.shared.saveTimezoneOffset(timezone.offsetHours, name: timezone.name)
        
        #if DEBUG
        print("[TimezoneSelectionView] ✅ Selected timezone: \(timezone.name) (UTC\(timezone.offsetHours))")
        #endif
        
        // Notify parent that timezone was selected
        onTimezoneSelected()
    }
}

// MARK: - Preview

struct TimezoneSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        TimezoneSelectionView {
            print("Timezone selected")
        }
    }
}
