import SwiftUI

struct FolderBrowserView: View {
    let accessToken: String
    let folderId: String?

    @State private var items: [OneDriveModels.Item] = []
    @State private var errorMessage: String = ""
    @State private var isLoading = false
    @State private var selectedFile: OneDriveModels.FileRef? = nil
    @State private var navigateToMain = false

    var body: some View {
        NavigationStack {
            List(items) { item in
                if item.isFolder {
                    NavigationLink(
                        destination: FolderBrowserView(accessToken: accessToken, folderId: item.id)
                    ) {
                        Label(item.name, systemImage: "folder")
                    }
                } else {
                    Button {
                        let ref = OneDriveModels.FileRef(id: item.id, name: item.name, parentId: folderId)
                        OneDriveModels.FileSelectionStore.save(ref)
                        selectedFile = ref
                        navigateToMain = true
                    } label: {
                        Label(item.name, systemImage: "doc")
                    }
                }
            }
            .navigationTitle("OneDrive")
            .onAppear { loadItems() }
            .overlay {
                if isLoading { ProgressView("Loading...") }
            }
            .alert(isPresented: .constant(!errorMessage.isEmpty)) {
                Alert(title: Text("Error"),
                      message: Text(errorMessage),
                      dismissButton: .default(Text("OK")))
            }
            .background(
                NavigationLink(isActive: $navigateToMain) {
                    Group {
                        if let file = selectedFile {
                            MainCheckbookView(accessToken: accessToken, fileRef: file)
                        } else {
                            EmptyView()
                        }
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            )
        }
    }

    private func loadItems() {
        isLoading = true
        errorMessage = ""
        OneDriveAPI.listChildren(accessToken: accessToken, folderId: folderId) { (result: Result<[OneDriveModels.Item], Error>) in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let children):
                    self.items = children
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

