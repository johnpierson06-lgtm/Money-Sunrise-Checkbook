import SwiftUI
import Foundation

struct UIAccount: Identifiable, Hashable {
    let id: Int
    let name: String
    let openingBalance: Decimal
    var currentBalance: Decimal
}

struct AccountsView: View {
    @State private var accounts: [UIAccount] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var showPasswordPrompt = true  // Show immediately on file open
    @State private var enteredPassword = ""
    @State private var isProcessingPassword = false
    @State private var presenterVC: UIViewController? = nil
    @State private var passwordErrorMessage: String? = nil  // NEW: Track password errors

    var body: some View {
        NavigationStack {
            Group {
                if isLoading || isProcessingPassword {
                    VStack(spacing: 16) {
                        ProgressView()
                        if isProcessingPassword {
                            Text("Decrypting file...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 20) {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Button("Try Again") {
                            // Clear error and show password prompt again
                            self.errorMessage = nil
                            self.showPasswordPrompt = true
                            self.enteredPassword = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if accounts.isEmpty && !showPasswordPrompt {
                    VStack(spacing: 20) {
                        Text("No accounts loaded")
                            .font(.headline)
                        Text("Please enter the password to decrypt your Money file")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Enter Password") {
                            self.showPasswordPrompt = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        refreshAccounts()
                    }
                    .disabled(isLoading || isProcessingPassword)
                }
            }
            .sheet(isPresented: $showPasswordPrompt) {
                PasswordPromptView(
                    password: $enteredPassword,
                    errorMessage: passwordErrorMessage,  // Pass error message
                    onSubmit: { password in
                        passwordErrorMessage = nil  // Clear error on new attempt
                        handlePasswordSubmit(password: password)
                    },
                    onCancel: {
                        showPasswordPrompt = false
                        passwordErrorMessage = nil
                        if accounts.isEmpty {
                            errorMessage = "Password required to access Money file"
                        }
                    }
                )
            }
        }
        .background(ViewControllerResolver { vc in self.presenterVC = vc })
    }
    
    private func handlePasswordSubmit(password: String) {
        showPasswordPrompt = false
        isProcessingPassword = true
        errorMessage = nil
        
        // Save password to keychain
        do {
            try PasswordStore.shared.save(password: password)
            #if DEBUG
            print("[AccountsView] Password saved to keychain")
            #endif
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to save password: \(error.localizedDescription)"
                self.isProcessingPassword = false
            }
            return
        }
        
        // Load accounts with the new password
        loadAccounts()
    }
    
    private func loadAccounts() {
        if !isProcessingPassword {
            isLoading = true
        }
        errorMessage = nil
        
        OneDriveFileManager.shared.ensureLocalMnyFile(presentingViewController: presenterVC) { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to get file URL: \(error.localizedDescription)"
                    self.isLoading = false
                    self.isProcessingPassword = false
                    return
                }
                if url == nil {
                    self.errorMessage = "No file selected. Go to OneDrive and pick a .mny file."
                    self.isLoading = false
                    self.isProcessingPassword = false
                    return
                }
                
                // Proceed to decrypt and parse
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        // Use MoneyFileService to read accounts
                        // This will use the password from PasswordStore
                        let summaries = try MoneyFileService.readAccountSummaries()
                        
                        // Map to UIAccount with calculated current balance
                        let uiAccounts = summaries.map { s in
                            UIAccount(id: s.id, name: s.name, openingBalance: s.beginningBalance, currentBalance: s.currentBalance)
                        }
                        
                        DispatchQueue.main.async {
                            self.accounts = uiAccounts
                            self.isLoading = false
                            self.isProcessingPassword = false
                            
                            #if DEBUG
                            print("[AccountsView] ✅ Successfully loaded \(uiAccounts.count) accounts")
                            #endif
                        }
                    } catch {
                        DispatchQueue.main.async {
                            // Check if it's a specific password error
                            if let decryptError = error as? MoneyDecryptorBridgeError,
                               decryptError == .badPassword {
                                // Password verification failed - re-prompt immediately
                                self.passwordErrorMessage = "Incorrect password. Please try again."
                                self.enteredPassword = ""  // Clear the wrong password
                                self.showPasswordPrompt = true  // Show prompt again
                                self.isLoading = false
                                self.isProcessingPassword = false
                                
                                #if DEBUG
                                print("[AccountsView] ❌ Password verification failed - re-prompting user")
                                #endif
                            } else {
                                // Other errors - show error screen
                                let errorDesc = error.localizedDescription.lowercased()
                                if errorDesc.contains("password") || errorDesc.contains("decrypt") {
                                    self.errorMessage = "Incorrect password. Please try again."
                                } else {
                                    self.errorMessage = error.localizedDescription
                                }
                                
                                self.isLoading = false
                                self.isProcessingPassword = false
                                
                                #if DEBUG
                                print("[AccountsView] ❌ Error loading accounts: \(error)")
                                #endif
                            }
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
                    // After refresh, prompt for password again
                    self.showPasswordPrompt = true
                }
            }
        }
    }
}

// MARK: - Password Prompt View

struct PasswordPromptView: View {
    @Binding var password: String
    let errorMessage: String?  // NEW: Optional error message to display
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPasswordFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: errorMessage != nil ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(errorMessage != nil ? .red : .blue)
                    .padding(.top, 40)
                
                // Title and description
                VStack(spacing: 8) {
                    Text(errorMessage != nil ? "Incorrect Password" : "Enter File Password")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("This Money file is password-protected.\nEnter your password to decrypt and open it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isPasswordFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            handleSubmit()
                        }
                }
                .padding(.horizontal)
                
                // Info text
                VStack(spacing: 4) {
                    Text("💡 Tip")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Text("If your file doesn't have a password, leave this field blank and tap Continue.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button {
                        handleSubmit()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            // Auto-focus the password field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isPasswordFieldFocused = true
            }
        }
    }
    
    private func handleSubmit() {
        dismiss()
        onSubmit(password)
    }
}

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView()
    }
}

