//
//  SyncView.swift
//  CheckbookApp
//
//  View for syncing local transactions and payees to OneDrive Money file
//

import SwiftUI
import Foundation

struct SyncView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var coordinator: AppCoordinator
    
    @State private var unsyncedTransactionCount: Int = 0
    @State private var unsyncedPayeeCount: Int = 0
    @State private var isLoading = true
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var syncProgress: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                                .padding(.top, 20)
                            
                            Text("Sync to OneDrive")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Upload local changes to your Money file")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)
                        
                        // Status Cards
                        if isLoading {
                            ProgressView("Loading sync status...")
                                .padding()
                        } else {
                            VStack(spacing: 16) {
                                // Transactions Card
                                SyncStatusCard(
                                    title: "Transactions",
                                    count: unsyncedTransactionCount,
                                    icon: "dollarsign.circle.fill",
                                    color: .green
                                )
                                
                                // Payees Card
                                SyncStatusCard(
                                    title: "Payees",
                                    count: unsyncedPayeeCount,
                                    icon: "person.circle.fill",
                                    color: .orange
                                )
                            }
                            .padding(.horizontal)
                        }
                        
                        // Progress Message
                        if isSyncing && !syncProgress.isEmpty {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text(syncProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Error Message
                        if let errorMessage = errorMessage {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                
                                Spacer()
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Success Message
                        if let successMessage = successMessage {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                
                                Text(successMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                
                                Spacer()
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Sync Button
                        if !isLoading {
                            Button {
                                performSync()
                            } label: {
                                HStack {
                                    Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                                        .rotationEffect(.degrees(isSyncing ? 360 : 0))
                                        .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                                    
                                    Text(isSyncing ? "Syncing..." : "Sync Now")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canSync ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(!canSync || isSyncing)
                            .padding(.horizontal)
                        }
                        
                        // Info Section
                        VStack(alignment: .leading, spacing: 12) {
                            Label("How Sync Works", systemImage: "info.circle.fill")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                SyncInfoRow(number: "1", text: "Transactions and payees are inserted into a temporary .mny file")
                                SyncInfoRow(number: "2", text: "Local records are cleared from the SQLite database")
                                SyncInfoRow(number: "3", text: "The file is uploaded to OneDrive as Money_Test_YYYYMMDD_hhmmss.mny")
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                    }
                }
                
                // Loading Overlay
                if isSyncing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                }
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isSyncing)
                }
            }
        }
        .onAppear {
            loadSyncStatus()
        }
    }
    
    // MARK: - Computed Properties
    
    private var canSync: Bool {
        return unsyncedTransactionCount > 0 || unsyncedPayeeCount > 0
    }
    
    // MARK: - Methods
    
    private func loadSyncStatus() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Count unsynced transactions
                let transactions = try LocalDatabaseManager.shared.getUnsyncedTransactions()
                let transactionCount = transactions.count
                
                // Count unsynced payees
                let payees = try LocalDatabaseManager.shared.getUnsyncedPayees()
                let payeeCount = payees.count
                
                DispatchQueue.main.async {
                    self.unsyncedTransactionCount = transactionCount
                    self.unsyncedPayeeCount = payeeCount
                    self.isLoading = false
                    
                    #if DEBUG
                    print("[SyncView] Loaded sync status: \(transactionCount) transactions, \(payeeCount) payees")
                    #endif
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load sync status: \(error.localizedDescription)"
                    self.isLoading = false
                    
                    #if DEBUG
                    print("[SyncView] ❌ Error loading sync status: \(error)")
                    #endif
                }
            }
        }
    }
    
    private func performSync() {
        guard !isSyncing else { return }
        
        isSyncing = true
        errorMessage = nil
        successMessage = nil
        syncProgress = "Preparing to sync..."
        
        Task {
            do {
                // Get unsynced counts before sync
                let transactions = try LocalDatabaseManager.shared.getUnsyncedTransactions()
                let payees = try LocalDatabaseManager.shared.getUnsyncedPayees()
                let totalCount = transactions.count + payees.count
                
                #if DEBUG
                print("[SyncView] Starting sync for \(transactions.count) transactions and \(payees.count) payees")
                #endif
                
                // Update progress
                await MainActor.run {
                    syncProgress = "Decrypting Money file..."
                }
                
                // Use the new SyncService with mdb-tools
                try await SyncService.shared.syncToMoneyFile()
                
                // Success!
                await MainActor.run {
                    self.isSyncing = false
                    self.syncProgress = ""
                    self.successMessage = """
                    Successfully synced \(totalCount) record(s) to OneDrive!
                    
                    ⚠️ IMPORTANT: To see transactions in Money:
                    1. Open file in Money Desktop
                    2. Go to File → Database Maintenance
                    3. Click "Validate and Repair"
                    
                    This rebuilds indexes so Money can see new data.
                    """
                    self.unsyncedTransactionCount = 0
                    self.unsyncedPayeeCount = 0
                    
                    #if DEBUG
                    print("[SyncView] ✅ Sync completed successfully")
                    #endif
                    
                    // Don't auto-dismiss - let user read the message
                }
            } catch SyncService.SyncError.noUnsyncedData {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncProgress = ""
                    self.errorMessage = "No unsynced data to upload"
                    
                    #if DEBUG
                    print("[SyncView] ℹ️ No unsynced data")
                    #endif
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncProgress = ""
                    self.errorMessage = "Sync failed: \(error.localizedDescription)"
                    
                    #if DEBUG
                    print("[SyncView] ❌ Sync failed: \(error)")
                    #endif
                }
            }
        }
    }
    

}

// MARK: - Supporting Views

struct SyncStatusCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(count) unsynced")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(count > 0 ? color : .gray)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct SyncInfoRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case noParentFolder
    case noAccessToken
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .noParentFolder:
            return "Could not determine OneDrive folder location"
        case .noAccessToken:
            return "Could not obtain access token for OneDrive"
        case .uploadFailed:
            return "Upload to OneDrive failed"
        }
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let yyyyMMddHHmmss: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

// MARK: - Preview

struct SyncView_Previews: PreviewProvider {
    static var previews: some View {
        SyncView()
            .environmentObject(AppCoordinator.shared)
    }
}
