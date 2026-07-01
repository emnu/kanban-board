import Foundation
import CryptoKit
import Combine

public enum SyncStatus: String, Codable {
    case disconnected = "Not Connected"
    case connecting = "Connecting..."
    case synced = "Synced with Google Drive"
    case syncing = "Syncing..."
    case error = "Sync Error"
    case offline = "Offline"
}

public class GoogleDriveSync: ObservableObject {
    public static let shared = GoogleDriveSync()
    
    private let serviceName = "com.kanbanapp.googledrive"
    private let accountRefreshToken = "refreshToken"
    private let accountAccessToken = "accessToken"
    private let accountClientId = "clientId"
    
    @Published public var status: SyncStatus = .disconnected
    @Published public var lastSyncTime: Date? = nil
    @Published var lastError: String? = nil
    
    private var codeVerifier: String?
    
    public init() {
        // Load initial status
        if hasSavedCredentials() {
            self.status = .offline // Or check in background
        }
    }
    
    public static let defaultClientId = "673711859742-5p9du971aqiibaoo34o4ng8emjvkqoqe.apps.googleusercontent.com"
    
    public var redirectUri: String {
        return "com.kanbanapp.oauth:/oauth2redirect"
    }
    
    public var clientId: String {
        get {
            let saved = KeychainHelper.shared.readString(service: serviceName, account: accountClientId) ?? ""
            return saved.isEmpty ? GoogleDriveSync.defaultClientId : saved
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.shared.delete(service: serviceName, account: accountClientId)
            } else {
                KeychainHelper.shared.saveString(newValue, service: serviceName, account: accountClientId)
            }
            objectWillChange.send()
        }
    }
    
    public func hasSavedCredentials() -> Bool {
        return !clientId.isEmpty && KeychainHelper.shared.readString(service: serviceName, account: accountRefreshToken) != nil
    }
    
    public func disconnect() {
        KeychainHelper.shared.delete(service: serviceName, account: accountRefreshToken)
        KeychainHelper.shared.delete(service: serviceName, account: accountAccessToken)
        status = .disconnected
        lastSyncTime = nil
        lastError = nil
    }
    
    // MARK: - OAuth Flow
    
    public func startAuthorizationURL() -> URL? {
        guard !clientId.isEmpty else { return nil }
        
        // Generate PKCE code verifier and challenge
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        self.codeVerifier = verifier
        
        let verifierData = verifier.data(using: .ascii)!
        let hash = SHA256.hash(data: verifierData)
        let challenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        
        return components.url
    }
    
    public func handleRedirectURL(_ url: URL) async -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            DispatchQueue.main.async {
                self.lastError = "Authorization code not found in redirect URL."
                self.status = .error
            }
            return false
        }
        
        return await exchangeCodeForToken(code: code)
    }
    
    private func exchangeCodeForToken(code: String) async -> Bool {
        guard let codeVerifier = self.codeVerifier else {
            updateStatus(.error, error: "Missing PKCE code verifier.")
            return false
        }
        
        updateStatus(.connecting)
        
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorStr = String(data: data, encoding: .utf8) ?? "Unknown token exchange error"
                updateStatus(.error, error: "Failed to exchange code: \(errorStr)")
                return false
            }
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            KeychainHelper.shared.saveString(tokenResponse.access_token, service: serviceName, account: accountAccessToken)
            if let refresh = tokenResponse.refresh_token {
                KeychainHelper.shared.saveString(refresh, service: serviceName, account: accountRefreshToken)
            }
            
            updateStatus(.synced)
            return true
        } catch {
            updateStatus(.error, error: "Token exchange network error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Token Refresh
    
    private func getValidAccessToken() async -> String? {
        guard let refreshToken = KeychainHelper.shared.readString(service: serviceName, account: accountRefreshToken) else {
            updateStatus(.disconnected)
            return nil
        }
        
        // Refresh token immediately to ensure access token is fresh (simplifies access token expiry check)
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // If refresh token is revoked
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                    disconnect()
                }
                let errorStr = String(data: data, encoding: .utf8) ?? "Refresh failed"
                updateStatus(.error, error: "Failed to refresh token: \(errorStr)")
                return nil
            }
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            KeychainHelper.shared.saveString(tokenResponse.access_token, service: serviceName, account: accountAccessToken)
            return tokenResponse.access_token
        } catch {
            updateStatus(.offline, error: "Network offline: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Drive Sync Operations
    
    public func fetchRemoteData() async -> (KanbanData?, String?) {
        guard let token = await getValidAccessToken() else {
            return (nil, "Unauthorized: Please connect to Google Drive.")
        }
        
        updateStatus(.syncing)
        
        // 1. Search for file
        let query = "name='macos_kanban_data.json' and trashed=false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            updateStatus(.error, error: "Encoding query error")
            return (nil, "Encoding query error")
        }
        
        let searchUrl = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,modifiedTime)")!
        var request = URLRequest(url: searchUrl)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                updateStatus(.error, error: "Search failed")
                return (nil, "Google Drive search failed.")
            }
            
            let searchResponse = try JSONDecoder().decode(DriveSearchResponse.self, from: data)
            
            guard let file = searchResponse.files.first else {
                // File doesn't exist yet!
                updateStatus(.synced)
                return (nil, nil) // Remote file not found, no data yet
            }
            
            // 2. Download file
            let downloadUrl = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!
            var downloadRequest = URLRequest(url: downloadUrl)
            downloadRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (fileData, fileResponse) = try await URLSession.shared.data(for: downloadRequest)
            guard let httpFileResponse = fileResponse as? HTTPURLResponse, httpFileResponse.statusCode == 200 else {
                updateStatus(.error, error: "Download failed")
                return (nil, "Failed to download remote file.")
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let kanbanData = try decoder.decode(KanbanData.self, from: fileData)
            
            updateStatus(.synced)
            DispatchQueue.main.async {
                self.lastSyncTime = Date()
            }
            return (kanbanData, file.id)
            
        } catch {
            updateStatus(.error, error: error.localizedDescription)
            return (nil, error.localizedDescription)
        }
    }
    
    public func uploadData(_ data: KanbanData, fileId: String?) async -> Bool {
        guard let token = await getValidAccessToken() else {
            return false
        }
        
        updateStatus(.syncing)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        guard let jsonData = try? encoder.encode(data) else {
            updateStatus(.error, error: "JSON encoding error")
            return false
        }
        
        do {
            if let fileId = fileId {
                // UPDATE existing file
                let uploadUrl = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=media")!
                var request = URLRequest(url: uploadUrl)
                request.httpMethod = "PATCH"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                
                let (resData, response) = try await URLSession.shared.upload(for: request, from: jsonData)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let err = String(data: resData, encoding: .utf8) ?? "Upload patch error"
                    updateStatus(.error, error: err)
                    return false
                }
                
                updateStatus(.synced)
                DispatchQueue.main.async {
                    self.lastSyncTime = Date()
                }
                return true
            } else {
                // CREATE new file
                // We use multipart/related to create with metadata + contents
                let boundary = "Boundary-\(UUID().uuidString)"
                let uploadUrl = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
                var request = URLRequest(url: uploadUrl)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                var body = Data()
                
                // Metadata part
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
                let metadata = ["name": "macos_kanban_data.json", "mimeType": "application/json"]
                let metadataData = try! JSONSerialization.data(withJSONObject: metadata)
                body.append(metadataData)
                body.append("\r\n".data(using: .utf8)!)
                
                // Media (content) part
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
                body.append(jsonData)
                body.append("\r\n".data(using: .utf8)!)
                
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                
                let (resData, response) = try await URLSession.shared.upload(for: request, from: body)
                guard let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 200 || httpResponse.statusCode == 201) else {
                    let err = String(data: resData, encoding: .utf8) ?? "Upload post error"
                    updateStatus(.error, error: err)
                    return false
                }
                
                updateStatus(.synced)
                DispatchQueue.main.async {
                    self.lastSyncTime = Date()
                }
                return true
            }
        } catch {
            updateStatus(.error, error: error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Helpers
    
    private func updateStatus(_ status: SyncStatus, error: String? = nil) {
        DispatchQueue.main.async {
            self.status = status
            self.lastError = error
        }
    }
}

// MARK: - OAuth Models

struct TokenResponse: Codable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String
    let token_type: String
}

struct DriveSearchResponse: Codable {
    struct DriveFile: Codable {
        let id: String
        let name: String
        let modifiedTime: String?
    }
    let files: [DriveFile]
}
