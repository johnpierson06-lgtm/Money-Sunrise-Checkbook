import SwiftUI
import Foundation

struct TransactionsView: View {
    let account: UIAccount
    
    @State private var transactions: [MoneyTransaction] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNewTransaction = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading transactions...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadTransactions()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if transactions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No Transactions")
                        .font(.headline)
                    Text("This account has no transactions yet.")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewTransaction) {
            NewTransactionView(account: account)
        }
        .onAppear {
            loadTransactions()
        }
    }
    
    // FIXED: Simplified to avoid Swift compiler crash
    private func loadTransactions() {
        isLoading = true
        errorMessage = nil
        
        // Use background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try MoneyFileService.ensureLocalFile()
                let decryptedData = try MoneyFileService.decryptFile()
                let allTransactions = try MoneyFileService.parseTransactions(from: decryptedData)
                
                // Filter by account ID - both are Int types
                let filtered = allTransactions.filter { transaction in
                    transaction.accountId == account.id
                }
                
                // Sort by date (newest first)
                let sorted = filtered.sorted { $0.date > $1.date }
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.transactions = sorted
                    self.isLoading = false
                }
            } catch {
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: MoneyTransaction
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.date, style: .date)
                    .font(.headline)
                if let memo = transaction.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(transaction.amount, format: .currency(code: "USD"))
                .font(.headline)
                .foregroundColor(transaction.amount >= 0 ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        TransactionsView(account: UIAccount(id: 1, name: "Sample Account", openingBalance: 1000, currentBalance: 1000))
    }
}
