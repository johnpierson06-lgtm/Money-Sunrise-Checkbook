import SwiftUI

struct TransactionsView: View {
    let accountId: Int
    let accountName: String
    
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
        .navigationTitle(accountName)
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
            NewTransactionView(accountId: accountId)
        }
        .onAppear {
            loadTransactions()
        }
    }
    
    // FIXED: Simplified to avoid Swift compiler crash
    private func loadTransactions() {
        isLoading = true
        errorMessage = nil
        
        // Synchronous version to avoid compiler crash with nested DispatchQueue
        do {
            _ = try MoneyFileService.ensureLocalFile()
            let decryptedData = try MoneyFileService.decryptFile()
            let allTransactions = try MoneyFileService.parseTransactions(from: decryptedData)
            
            // Filter by account
            let filtered = allTransactions.filter { $0.accountId == accountId }
            
            // Sort by date (newest first)
            let sorted = filtered.sorted { $0.date > $1.date }
            
            self.transactions = sorted
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
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
        TransactionsView(accountId: 1, accountName: "Sample Account")
    }
}
