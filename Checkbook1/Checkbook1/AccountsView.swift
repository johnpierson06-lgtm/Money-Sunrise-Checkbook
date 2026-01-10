import SwiftUI
import UIKit
import Foundation

struct UIAccount: Identifiable, Hashable {
    let id: Int
    let name: String
    let openingBalance: Decimal
    var currentBalance: Decimal
}

struct AccountsView: View {
    @State private var accounts: [UIAccount] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var showPasswordPrompt = false
    @State private var tempPassword = ""
    @State private var presenterVC: UIViewController? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage = errorMessage {
                    Text(errorMessage).foregroundColor(.red).multilineTextAlignment(.center).padding()
                } else {
                    List(accounts) { account in
                        NavigationLink(destination: TransactionsView(account: account)) {
                            HStack {
                                Text(account.name)
                                Spacer()
                                Text(NSDecimalNumber(decimal: account.currentBalance).doubleValue, format: .currency(code: Locale.current.currencyCode ?? "USD"))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                Button("Refresh") {
                    refreshAccounts()
                }
            }
            .onAppear {
                loadAccounts()
            }
            .alert("Enter Password", isPresented: $showPasswordPrompt) {
                Button("Cancel") {
                    showPasswordPrompt = false
                    isLoading = false
                }
                Button("Save") {
                    do {
                        try PasswordStore.shared.save(password: tempPassword)
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                    showPasswordPrompt = false
                    // Retry loading and parsing with saved password
                    loadAccounts()
                }
            } message: {
                VStack {
                    SecureField("Password", text: $tempPassword)
                        .textInputAutocapitalization(.never)
                        .privacySensitive()
                        .padding(.vertical, 4)
                }
            }
        }
        .background(ViewControllerResolver { vc in self.presenterVC = vc })
    }
    
    private func isJetHeader(_ data: Data) -> Bool {
        // Check first 512 bytes for ASCII "Standard Jet DB" or "Standard ACE DB"
        let headerLength = 512
        let checkData = data.prefix(headerLength)
        if let headerString = String(data: checkData, encoding: .ascii) {
            return headerString.contains("Standard Jet DB") || headerString.contains("Standard ACE DB")
        }
        return false
    }

    private func loadAccounts() {
        isLoading = true
        errorMessage = nil
        OneDriveFileManager.shared.ensureLocalMnyFile(presentingViewController: presenterVC) { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to get file URL: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                if url == nil {
                    self.errorMessage = "No file selected. Go to OneDrive and pick a .mny file."
                    self.isLoading = false
                    return
                }
                // Proceed when url is non-nil or if your API doesn't require it here
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        // Use MoneyMDB to read accounts (requires mdbtools_c)
                        let summaries = try MoneyFileService.readAccountSummaries()
                        // For now, set currentBalance = openingBalance until TRN parsing is implemented
                        let uiAccounts = summaries.map { s in
                            UIAccount(id: s.id, name: s.name, openingBalance: s.beginningBalance, currentBalance: s.beginningBalance)
                        }
                        DispatchQueue.main.async {
                            self.accounts = uiAccounts
                            self.isLoading = false
                        }
                    } catch let err as MoneyDecrypterError {
                        DispatchQueue.main.async {
                            switch err {
                            case .badPassword:
                                self.errorMessage = "Bad password or unsupported format."
                            case .unsupportedFormat(let msg):
                                self.errorMessage = "Unsupported Money format or missing mdbtools.\n\(msg)"
                            default:
                                self.errorMessage = String(describing: err)
                            }
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
    }

    private func refreshAccounts() {
        isLoading = true
        errorMessage = nil
        OneDriveFileManager.shared.refreshLocalMnyFile { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to refresh file: \(error.localizedDescription)"
                    self.isLoading = false
                } else {
                    loadAccounts()
                }
            }
        }
    }
}

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView()
    }
}

