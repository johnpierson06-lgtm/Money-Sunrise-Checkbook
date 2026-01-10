import SwiftUI

struct TransactionsView: View {
    let account: UIAccount
    @State private var transactions: [MoneyTransaction] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(transactions, id: \.id) { transaction in
                    VStack(alignment: .leading) {
                        Text(transaction.date, style: .date)
                            .font(.headline)
                        Text("Amount: \(transaction.amount, specifier: "%.2f")")
                        Text("Category/Payee: Placeholder")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Transactions")
        .toolbar {
            NavigationLink("New") {
                NewTransactionView(account: account)
            }
        }
        .onAppear {
            loadTransactions()
        }
    }

    private func loadTransactions() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try MoneyFileService.ensureLocalFile()
                let decryptedData = try MoneyFileService.decryptFile()
                let parsedTransactions = try MoneyFileService.parseTransactions(from: decryptedData)
                // TODO: Filter by account once IDs are aligned (Int vs UUID) and parsing is implemented
                let filtered = parsedTransactions
                let sorted = filtered.sorted { $0.date > $1.date }

                DispatchQueue.main.async {
                    self.transactions = sorted
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

struct TransactionsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TransactionsView(account: UIAccount(id: 1, name: "Checking", openingBalance: 1000, currentBalance: 1000))
        }
    }
}
