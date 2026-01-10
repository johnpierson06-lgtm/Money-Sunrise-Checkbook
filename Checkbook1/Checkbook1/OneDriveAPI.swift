import Foundation

enum OneDriveAPI {
    static func listChildren(accessToken: String,
                             folderId: String?,
                             completion: @escaping (Result<[OneDriveModels.Item], Error>) -> Void) {
        let base = "https://graph.microsoft.com/v1.0/me/drive"
        let urlStr = (folderId == nil) ? "\(base)/root/children" : "\(base)/items/\(folderId!)/children"
        guard let url = URL(string: urlStr) else {
            let err = NSError(domain: "OneDriveAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            completion(Result<[OneDriveModels.Item], Error>.failure(err))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(Result<[OneDriveModels.Item], Error>.failure(error))
                return
            }

            guard let http = response as? HTTPURLResponse else {
                let err = NSError(domain: "OneDriveAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
                completion(Result<[OneDriveModels.Item], Error>.failure(err))
                return
            }

            // Non-2xx -> attempt to surface Graph error message
            guard (200...299).contains(http.statusCode) else {
                if let data = data,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errObj = obj["error"] as? [String: Any],
                   let message = errObj["message"] as? String {
                    let err = NSError(domain: "OneDriveAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                    completion(Result<[OneDriveModels.Item], Error>.failure(err))
                } else {
                    let err = NSError(domain: "OneDriveAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                    completion(Result<[OneDriveModels.Item], Error>.failure(err))
                }
                return
            }

            guard let data = data else {
                completion(Result<[OneDriveModels.Item], Error>.failure(NSError(domain: "OneDriveAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Empty response"])) )
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let values = (json?["value"] as? [[String: Any]]) ?? []
                let items: [OneDriveModels.Item] = values.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let name = dict["name"] as? String else { return nil }
                    let folder = dict["folder"] != nil
                    return OneDriveModels.Item(id: id, name: name, isFolder: folder)
                }
                completion(Result<[OneDriveModels.Item], Error>.success(items))
            } catch {
                completion(Result<[OneDriveModels.Item], Error>.failure(error))
            }
        }.resume()
    }
}
