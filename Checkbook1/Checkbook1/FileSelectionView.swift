import SwiftUI
import UIKit

struct FileSelectionView: View {
    @State private var items: [OneDriveModels.Item] = []
    @State private var path: [OneDriveModels.Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var navigateToAccounts = false
    @State private var breadcrumbs: [OneDriveModels.Item] = []
    @State private var currentFolderId: String? = nil
    @State private var accessToken: String? = nil
    @State private var presenterVC: UIViewController? = nil
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    if items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No items in this folder")
                                .foregroundColor(.secondary)
                            Text("Pull to refresh or change account.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(items, id: \.id) { item in
                            if item.isFolder {
                                Button {
                                    breadcrumbs.append(item)
                                    currentFolderId = item.id
                                    loadChildren(folderId: item.id)
                                } label: {
                                    Label(item.name, systemImage: "folder")
                                }
                            } else if item.name.lowercased().hasSuffix(".mny") {
                                HStack {
                                    Text(item.name)
                                    Spacer()
                                    Button("Select") {
                                        selectFile(item: item)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            } else {
                                Text(item.name)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(breadcrumbs.last?.name ?? "OneDrive")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Change account") {
                        AuthManager.shared.signOut { _ in
                            navigateToAccounts = false
                            // Pop back by clearing breadcrumbs and items
                            breadcrumbs = []
                            currentFolderId = nil
                            items = []
                        }
                    }
                }
            }
            .onAppear {
                loadChildren(folderId: currentFolderId)
            }
            .background(
                NavigationLink(
                    destination: AccountsView(),
                    isActive: $navigateToAccounts,
                    label: { EmptyView() }
                )
                .hidden()
            )
            .background(ViewControllerResolver { vc in self.presenterVC = vc })
        }
    }
    
    private func loadChildren(folderId: String?) {
        isLoading = true
        errorMessage = nil

        // If we already have a token in memory, use it directly
        if let token = accessToken {
            OneDriveAPI.listChildren(accessToken: token, folderId: folderId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let children):
                        self.items = children
                        self.isLoading = false
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
            return
        }

        // Try silent acquisition first
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, err in
            if let err = err {
                // Fallback to interactive sign-in
                AuthManager.shared.signIn(scopes: ["Files.Read", "Files.ReadWrite"], presentingViewController: presenterVC) { token, signInErr in
                    if let signInErr = signInErr {
                        DispatchQueue.main.async {
                            self.errorMessage = signInErr.localizedDescription
                            self.isLoading = false
                        }
                        return
                    }
                    guard let token = token else {
                        DispatchQueue.main.async {
                            self.errorMessage = "No access token"
                            self.isLoading = false
                        }
                        return
                    }
                    self.accessToken = token
                    OneDriveAPI.listChildren(accessToken: token, folderId: folderId) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let children):
                                self.items = children
                                self.isLoading = false
                            case .failure(let error):
                                self.errorMessage = error.localizedDescription
                                self.isLoading = false
                            }
                        }
                    }
                }
                return
            }
            guard let token = token else {
                DispatchQueue.main.async {
                    self.errorMessage = "No access token"
                    self.isLoading = false
                }
                return
            }
            self.accessToken = token
            OneDriveAPI.listChildren(accessToken: token, folderId: folderId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let children):
                        self.items = children
                        self.isLoading = false
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    private func selectFile(item: OneDriveModels.Item) {
        OneDriveFileManager.shared.saveSelectedFile(fileId: item.id, fileName: item.name, parentFolderId: breadcrumbs.last?.id)
        if let token = self.accessToken {
            OneDriveFileManager.shared.refreshLocalMnyFile(accessToken: token) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.navigateToAccounts = true
                    }
                }
            }
        } else {
            OneDriveFileManager.shared.refreshLocalMnyFile(presentingViewController: presenterVC) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.navigateToAccounts = true
                    }
                }
            }
        }
    }
}

struct FileSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        FileSelectionView()
    }
}
