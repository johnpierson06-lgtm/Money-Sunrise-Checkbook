import Foundation

enum OneDriveAPI {
    
    /// Upload a file to OneDrive
    static func uploadFile(accessToken: String,
                          fileURL: URL,
                          fileName: String,
                          parentFolderId: String,
                          completion: @escaping (Result<Void, Error>) -> Void) {
        
        let uploadURLString = "https://graph.microsoft.com/v1.0/me/drive/items/\(parentFolderId):/\(fileName):/content"
        
        guard let uploadURL = URL(string: uploadURLString) else {
            completion(.failure(NSError(domain: "OneDriveAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"])))
            return
        }
        
        guard let fileData = try? Data(contentsOf: fileURL) else {
            completion(.failure(NSError(domain: "OneDriveAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not read file data"])))
            return
        }
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "OneDriveAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let data = data,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errObj = obj["error"] as? [String: Any],
                   let message = errObj["message"] as? String {
                    completion(.failure(NSError(domain: "OneDriveAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])))
                } else {
                    completion(.failure(NSError(domain: "OneDriveAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])))
                }
                return
            }
            
            completion(.success(()))
        }.resume()
    }
    
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
