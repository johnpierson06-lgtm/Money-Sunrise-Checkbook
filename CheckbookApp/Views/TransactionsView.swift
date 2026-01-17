import SwiftUI
import Foundation

struct TransactionsView: View {
    let account: UIAccount
    
    @State private var transactions: [TransactionDetail] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNewTransaction = false
    @State private var currentPage = 0
    private let pageSize = 10
    
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
                    Text("This account has no posted transactions yet.")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(paginatedTransactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                    
                    // Load more button
                    if hasMorePages {
                        Button {
                            currentPage += 1
                        } label: {
                            HStack {
                                Spacer()
                                Text("Load More")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
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
    
    private var paginatedTransactions: [TransactionDetail] {
        let endIndex = min((currentPage + 1) * pageSize, transactions.count)
        return Array(transactions[0..<endIndex])
    }
    
    private var hasMorePages: Bool {
        (currentPage + 1) * pageSize < transactions.count
    }
    
    private func loadTransactions() {
        isLoading = true
        errorMessage = nil
        currentPage = 0
        
        // Use background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try MoneyFileService.ensureLocalFile()
                let password = (try? PasswordStore.shared.load()) ?? ""
                let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: url.path, password: password)
                
                let parser = MoneyFileParser(filePath: decryptedPath)
                
                // Parse all needed data
                let allTransactions = try parser.parseTransactions()
                let categories = try parser.parseCategories()
                let payees = try parser.parsePayees()
                
                // Create lookup dictionaries
                let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
                let payeeLookup = Dictionary(uniqueKeysWithValues: payees.map { ($0.id, $0) })
                
                // Filter posted transactions for this account
                let filtered = allTransactions.filter { transaction in
                    transaction.accountId == account.id && transaction.shouldCountInBalance
                }
                
                // Sort by date (newest first)
                let sorted = filtered.sorted { $0.date > $1.date }
                
                // Convert to TransactionDetail with names
                let details = sorted.map { transaction in
                    TransactionDetail(
                        transaction: transaction,
                        payees: payeeLookup,
                        categories: categoryLookup
                    )
                }
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.transactions = details
                    self.isLoading = false
                    
                    #if DEBUG
                    print("[TransactionsView] Loaded \(details.count) posted transactions for account \(account.id)")
                    #endif
                }
            } catch {
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    
                    #if DEBUG
                    print("[TransactionsView] Error loading transactions: \(error)")
                    #endif
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: TransactionDetail
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: transaction.date)
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Date
                Text(formattedDate)
                    .font(.headline)
                
                // Payee
                if let payee = transaction.payeeName {
                    Text(payee)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                // Category - with debug
                if let category = transaction.categoryName {
                    Text(category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .onAppear {
                            #if DEBUG
                            print("[TransactionRow] Displaying category: '\(category)' (bytes: \(Array(category.utf8)))")
                            #endif
                        }
                }
                
                // Memo
                if let memo = transaction.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .onAppear {
                            #if DEBUG
                            print("[TransactionRow] Memo: '\(memo)' (bytes: \(Array(memo.utf8)))")
                            #endif
                        }
                }
            }
            
            Spacer()
            
            // Amount
            Text(transaction.amount, format: .currency(code: Locale.current.currencyCode ?? "USD"))
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
