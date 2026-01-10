import SwiftUI

struct MainCheckbookView: View {
    let accessToken: String
    let fileRef: OneDriveModels.FileRef

    @State private var accounts: [UIAccount] = []
    @State private var isLoading = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Accounts").font(.largeTitle).bold()

            if isLoading {
                ProgressView("Loading…")
            } else if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            } else {
                List(accounts, id: \.id) { acct in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(acct.name).font(.headline)
                            Spacer()
                            Text(acct.currentBalance, format: .number)
                        }
                        HStack {
                            Button("New Transaction") {
                                print("New transaction for \(acct.name)")
                            }
                            .buttonStyle(.borderedProminent)

                            Spacer()

                            Button("View Transactions") {
                                print("View transactions for \(acct.name)")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Spacer()
            Text("File: \(fileRef.name)").font(.footnote).foregroundColor(.secondary)
        }
        .padding()
        .onAppear(perform: loadData)
    }

    private func loadData() {
        isLoading = true
        errorMessage = ""

        MoneyFileService.download(accessToken: accessToken, fileRef: fileRef) { result in
            switch result {
            case .success(let rawData):
                let decrypted = MoneyFileService.decrypt(rawData)
                let accounts = MoneyFileService.parseAccounts(from: decrypted)
                DispatchQueue.main.async {
                    self.accounts = accounts
                    self.isLoading = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
