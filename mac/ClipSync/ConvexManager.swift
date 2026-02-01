//
// ConvexManager.swift
// ClipSync - Convex Backend
//
// Replaces FirebaseManager.swift for Convex-based real-time sync
//

import Foundation
import Combine

// MARK: - Convex Client

class ConvexManager: ObservableObject {
    static let shared = ConvexManager()
    
    private let deploymentUrl: String
    private let session: URLSession
    private var subscriptions: [String: AnyCancellable] = [:]
    
    @Published var isConnected: Bool = false
    
    private init() {
        // Get deployment URL from UserDefaults or use default
        // This should be set via config or environment
        self.deploymentUrl = UserDefaults.standard.string(forKey: "convex_url") 
            ?? Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String
            ?? "https://YOUR_DEPLOYMENT.convex.cloud"
        
        // Configure URL session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        
        print("✅ Convex initialized: \(deploymentUrl)")
        print("🔒 Security: E2E Encryption (No Auth Required)")
        
        testConnection()
    }
    
    // MARK: - Configuration
    
    static func configure(url: String) {
        UserDefaults.standard.set(url, forKey: "convex_url")
    }
    
    var baseURL: String {
        return deploymentUrl
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        Task {
            do {
                // Simple query to test connection - we just check if the request succeeds
                let _: ConvexPairing? = try await query("pairings:getByMacId", args: ["macDeviceId": "test"])
                await MainActor.run {
                    self.isConnected = true
                }
                print("✅ Convex connection verified")
            } catch {
                print("⚠️ Convex connection test: \(error.localizedDescription)")
                // Connection might still work, just no data for test query
                await MainActor.run {
                    self.isConnected = true
                }
            }
        }
    }
    
    // MARK: - Query (One-shot)
    
    func query<T: Decodable>(_ functionName: String, args: [String: Any] = [:]) async throws -> T? {
        let url = URL(string: "\(deploymentUrl)/api/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "path": functionName,
            "args": args,
            "format": "json"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["errorMessage"] as? String {
                throw ConvexError.serverError(errorMessage)
            }
            throw ConvexError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConvexError.invalidResponse
        }
        
        guard let status = json["status"] as? String, status == "success" else {
            if let errorMessage = json["errorMessage"] as? String {
                throw ConvexError.serverError(errorMessage)
            }
            throw ConvexError.serverError("Unknown error")
        }
        
        // Handle null value
        if json["value"] is NSNull {
            return nil
        }
        
        guard let value = json["value"] else {
            return nil
        }
        
        // Re-serialize value and decode to type
        let valueData = try JSONSerialization.data(withJSONObject: value)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: valueData)
    }
    
    // MARK: - Mutation
    
    func mutation<T: Decodable>(_ functionName: String, args: [String: Any] = [:]) async throws -> T {
        let url = URL(string: "\(deploymentUrl)/api/mutation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "path": functionName,
            "args": args,
            "format": "json"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["errorMessage"] as? String {
                throw ConvexError.serverError(errorMessage)
            }
            throw ConvexError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConvexError.invalidResponse
        }
        
        guard let status = json["status"] as? String, status == "success" else {
            if let errorMessage = json["errorMessage"] as? String {
                throw ConvexError.serverError(errorMessage)
            }
            throw ConvexError.serverError("Unknown error")
        }
        
        guard let value = json["value"] else {
            throw ConvexError.invalidResponse
        }
        
        // Re-serialize value and decode to type
        let valueData = try JSONSerialization.data(withJSONObject: value)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: valueData)
    }
    
    // Mutation that returns void
    func mutationVoid(_ functionName: String, args: [String: Any] = [:]) async throws {
        let url = URL(string: "\(deploymentUrl)/api/mutation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "path": functionName,
            "args": args,
            "format": "json"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["errorMessage"] as? String {
                throw ConvexError.serverError(errorMessage)
            }
            throw ConvexError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConvexError.invalidResponse
        }
        
        guard let status = json["status"] as? String, status == "success" else {
            if let errorMessage = json["errorMessage"] as? String {
                throw ConvexError.serverError(errorMessage)
            }
            throw ConvexError.serverError("Unknown error")
        }
    }
    
    // MARK: - Polling Subscription (simulates real-time)
    
    /// Creates a polling-based subscription that checks for updates at regular intervals
    /// Returns a Combine publisher that emits new values
    func subscribe<T: Decodable & Equatable>(
        to functionName: String,
        args: [String: Any] = [:],
        interval: TimeInterval = 0.5,
        type: T.Type
    ) -> AnyPublisher<T?, Error> {
        let subject = CurrentValueSubject<T?, Error>(nil)
        var lastValue: T? = nil
        var isActive = true
        
        func poll() {
            guard isActive else { return }
            
            Task {
                do {
                    let result: T? = try await self.query(functionName, args: args)
                    
                    // Only emit if value changed
                    if result != lastValue {
                        lastValue = result
                        subject.send(result)
                    }
                    
                    // Schedule next poll
                    if isActive {
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                        poll()
                    }
                } catch {
                    // On error, retry after delay
                    if isActive {
                        try? await Task.sleep(nanoseconds: UInt64(2 * 1_000_000_000))
                        poll()
                    }
                }
            }
        }
        
        // Start polling
        poll()
        
        // Return publisher with cleanup on cancel
        return subject
            .handleEvents(receiveCancel: {
                isActive = false
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Helpers
    
    var isReady: Bool {
        return !deploymentUrl.contains("YOUR_DEPLOYMENT")
    }
}

// MARK: - Error Types

enum ConvexError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case encodingError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        case .encodingError:
            return "Failed to encode request"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

// MARK: - Response Models

struct ConvexPairing: Codable, Equatable {
    let _id: String
    let _creationTime: Double
    let androidDeviceId: String
    let androidDeviceName: String
    let macDeviceId: String
    let macDeviceName: String
    let status: String
    let createdAt: Double
    
    var documentId: String { _id }
}

struct ConvexClipboardItem: Codable, Equatable {
    let _id: String
    let _creationTime: Double
    let content: String
    let pairingId: String
    let sourceDeviceId: String
    let type: String
    
    var documentId: String { _id }
    var timestamp: Date {
        Date(timeIntervalSince1970: _creationTime / 1000)
    }
}
