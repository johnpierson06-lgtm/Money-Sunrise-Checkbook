import SwiftUI
import Foundation

struct TransactionsView: View {
    let account: UIAccount
    
    @State private var transactions: [TransactionDetail] = []
    @State private var localTransactions: [TransactionDetail] = []  // From local DB
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
            } else if transactions.isEmpty && localTransactions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No Transactions")
                        .font(.headline)
                    Text("Tap + to add your first transaction.")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    // Show local transactions first (unsynced)
                    if !localTransactions.isEmpty {
                        Section {
                            ForEach(paginatedLocalTransactions) { transaction in
                                TransactionRow(transaction: transaction, isLocal: true)
                            }
                        } header: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Unsynced Transactions")
                            }
                        }
                    }
                    
                    // Show synced transactions from file
                    if !transactions.isEmpty {
                        Section(localTransactions.isEmpty ? "" : "Synced Transactions") {
                            ForEach(paginatedTransactions) { transaction in
                                TransactionRow(transaction: transaction, isLocal: false)
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
        .onChange(of: showingNewTransaction) { oldValue, newValue in
            // Reload when sheet is dismissed
            print("🔄 Sheet state changed: \(oldValue) -> \(newValue)")
            if oldValue && !newValue {
                print("📥 Reloading transactions after sheet dismissed...")
                loadTransactions()
            }
        }
    }
    
    private var paginatedLocalTransactions: [TransactionDetail] {
        return localTransactions  // Show all local transactions
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
                
                // Load local transactions
                let localTxns = try LocalDatabaseManager.shared.getUnsyncedTransactions()
                print("🔍 Got \(localTxns.count) unsynced transactions from database")
                let localFiltered = localTxns.filter { $0.hacct == account.id }
                print("🔍 Filtered to \(localFiltered.count) for account \(account.id)")
                
                // Convert local transactions to TransactionDetail
                // We'll create simplified MoneyTransaction objects for display
                let localDetails = localFiltered.map { localTxn -> TransactionDetail in
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MM/dd/yy HH:mm:ss"
                    let date = dateFormatter.date(from: localTxn.dt) ?? Date()
                    
                    let payeeName = localTxn.lHpay.flatMap { payeeLookup[$0]?.name }
                    let categoryName = localTxn.hcat.flatMap { categoryLookup[$0]?.name }
                    
                    return TransactionDetail(
                        id: localTxn.htrn,
                        date: date,
                        amount: localTxn.amt,
                        payeeName: payeeName,
                        categoryName: categoryName,
                        memo: localTxn.mMemo
                    )
                }.sorted { $0.date > $1.date }
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.transactions = details
                    self.localTransactions = localDetails
                    self.isLoading = false
                    
                    #if DEBUG
                    print("[TransactionsView] Loaded \(details.count) synced + \(localDetails.count) local transactions for account \(account.id)")
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
    let isLocal: Bool
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: transaction.date)
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // Date
                    Text(formattedDate)
                        .font(.headline)
                    
                    // Unsynced indicator
                    if isLocal {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
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
