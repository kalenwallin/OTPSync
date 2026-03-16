//
// ConvexManager.swift
// OTPSync - Convex Backend
//
// Replaces FirebaseManager.swift for Convex-based real-time sync
//

import AppKit
import Combine
import Foundation

// MARK: - Convex Client

class ConvexManager: ObservableObject {
    static let shared = ConvexManager()

    private let deploymentUrl: String
    private let session: URLSession
    private var subscriptions: [String: AnyCancellable] = [:]

    @Published var isConnected: Bool = false

    // WebSocket sync connection (replaces HTTP polling for subscriptions)
    private lazy var wsSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 0  // No timeout for long-lived WebSocket
        return URLSession(configuration: config)
    }()
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsSessionId = UUID().uuidString
    private var wsConnectionCount = 0
    private var wsQuerySetVersion = 0
    private var wsNextQueryId = 0
    private var wsMaxTimestamp: Any?
    private var wsActiveSubscriptions: [Int: WSSubscriptionInfo] = [:]
    private var wsReconnectDelay: TimeInterval = 1.0
    private var wsIsConnected = false
    private let wsLock = NSLock()
    private var wsReceiveTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        // Get deployment URL from UserDefaults or use default from Secrets
        self.deploymentUrl =
            UserDefaults.standard.string(forKey: "convex_url")
            ?? Secrets.convexURL

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
                let _: ConvexPairing? = try await query(
                    "pairings:getByMacId", args: ["macDeviceId": "test"])
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

        let sanitizedArgs = sanitizeArgs(args)
        let body: [String: Any] = [
            "path": functionName,
            "args": sanitizedArgs,
            "format": "json",
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            print("❌ ConvexManager: Invalid JSON object for query '\(functionName)'")
            throw ConvexError.encodingError
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorMessage = errorJson["errorMessage"] as? String
            {
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
        // JSONSerialization requires top-level arrays/dicts, so wrap primitives
        let valueData: Data
        if JSONSerialization.isValidJSONObject(value) {
            valueData = try JSONSerialization.data(withJSONObject: value)
        } else {
            // Handle primitive types (String, Number, Bool) by wrapping in array
            let wrapped = [value]
            let wrappedData = try JSONSerialization.data(withJSONObject: wrapped)
            // Decode the wrapped array and extract the single element
            guard let wrappedString = String(data: wrappedData, encoding: .utf8),
                wrappedString.count > 2
            else {
                throw ConvexError.decodingError
            }
            // Remove the array brackets to get just the primitive JSON
            let startIndex = wrappedString.index(wrappedString.startIndex, offsetBy: 1)
            let endIndex = wrappedString.index(wrappedString.endIndex, offsetBy: -1)
            let primitiveJson = String(wrappedString[startIndex..<endIndex])
            guard let data = primitiveJson.data(using: .utf8) else {
                throw ConvexError.decodingError
            }
            valueData = data
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: valueData)
    }

    // MARK: - Mutation

    func mutation<T: Decodable>(_ functionName: String, args: [String: Any] = [:]) async throws -> T
    {
        let url = URL(string: "\(deploymentUrl)/api/mutation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let sanitizedArgs = sanitizeArgs(args)
        let body: [String: Any] = [
            "path": functionName,
            "args": sanitizedArgs,
            "format": "json",
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            print("❌ ConvexManager: Invalid JSON object for mutation '\(functionName)'")
            throw ConvexError.encodingError
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorMessage = errorJson["errorMessage"] as? String
            {
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
        // JSONSerialization requires top-level arrays/dicts, so wrap primitives
        let valueData: Data
        if JSONSerialization.isValidJSONObject(value) {
            valueData = try JSONSerialization.data(withJSONObject: value)
        } else {
            // Handle primitive types (String, Number, Bool) by wrapping in array
            let wrapped = [value]
            let wrappedData = try JSONSerialization.data(withJSONObject: wrapped)
            // Decode the wrapped array and extract the single element
            guard let wrappedString = String(data: wrappedData, encoding: .utf8),
                wrappedString.count > 2
            else {
                throw ConvexError.decodingError
            }
            // Remove the array brackets to get just the primitive JSON
            let startIndex = wrappedString.index(wrappedString.startIndex, offsetBy: 1)
            let endIndex = wrappedString.index(wrappedString.endIndex, offsetBy: -1)
            let primitiveJson = String(wrappedString[startIndex..<endIndex])
            guard let data = primitiveJson.data(using: .utf8) else {
                throw ConvexError.decodingError
            }
            valueData = data
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: valueData)
    }

    // Mutation that returns void
    func mutationVoid(_ functionName: String, args: [String: Any] = [:]) async throws {
        let url = URL(string: "\(deploymentUrl)/api/mutation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let sanitizedArgs = sanitizeArgs(args)
        let body: [String: Any] = [
            "path": functionName,
            "args": sanitizedArgs,
            "format": "json",
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            print("❌ ConvexManager: Invalid JSON object for mutation '\(functionName)'")
            throw ConvexError.encodingError
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorMessage = errorJson["errorMessage"] as? String
            {
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

    // MARK: - WebSocket Reactive Subscriptions

    private class WSSubscriptionInfo {
        let queryId: Int
        let functionName: String
        let args: [String: Any]
        let handleValue: (Any?) -> Void

        init(queryId: Int, functionName: String, args: [String: Any], handleValue: @escaping (Any?) -> Void) {
            self.queryId = queryId
            self.functionName = functionName
            self.args = args
            self.handleValue = handleValue
        }
    }

    /// WebSocket-based reactive subscription — Convex pushes updates in real-time
    /// when the underlying data changes. No polling interval needed.
    func subscribe<T: Decodable & Equatable>(
        to functionName: String,
        args: [String: Any] = [:],
        type: T.Type
    ) -> AnyPublisher<T?, Error> {
        let subject = CurrentValueSubject<T?, Error>(nil)

        wsLock.lock()
        let queryId = wsNextQueryId
        wsNextQueryId += 1
        wsLock.unlock()

        let info = WSSubscriptionInfo(
            queryId: queryId,
            functionName: functionName,
            args: args,
            handleValue: { [weak self] rawValue in
                guard let self = self else { return }
                if rawValue == nil || rawValue is NSNull {
                    subject.send(nil)
                    return
                }
                do {
                    let decoded: T? = try self.decodeWSValue(rawValue, type: type)
                    subject.send(decoded)
                } catch {
                    print("❌ ConvexWS: Decode error for \(functionName): \(error)")
                }
            }
        )

        wsLock.lock()
        wsActiveSubscriptions[queryId] = info
        let connected = wsIsConnected
        wsLock.unlock()

        if connected {
            sendAddQuery(queryId: queryId, functionName: functionName, args: args)
        } else {
            connectWebSocket()
        }

        return subject
            .handleEvents(receiveCancel: { [weak self] in
                self?.removeWSSubscription(queryId: queryId)
            })
            .eraseToAnyPublisher()
    }

    // MARK: - WebSocket Connection

    private func connectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        wsReceiveTask?.cancel()

        let wsUrlStr = deploymentUrl
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
            + "/api/sync"

        guard let url = URL(string: wsUrlStr) else {
            print("❌ ConvexWS: Invalid URL: \(wsUrlStr)")
            return
        }

        print("🔌 ConvexWS: Connecting to \(url.host ?? "unknown")...")

        let task = wsSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        // Send Connect message
        var connectMsg: [String: Any] = [
            "type": "Connect",
            "sessionId": wsSessionId,
            "connectionCount": wsConnectionCount,
            "lastCloseReason": wsConnectionCount == 0 ? "clean" : "Reconnecting",
        ]
        if let ts = wsMaxTimestamp {
            connectMsg["maxObservedTimestamp"] = ts
        }
        wsConnectionCount += 1
        sendWSMessage(connectMsg)

        // Re-subscribe all active queries in a single ModifyQuerySet
        wsLock.lock()
        let subs = Array(wsActiveSubscriptions.values)
        wsQuerySetVersion = 0
        wsLock.unlock()

        if !subs.isEmpty {
            let modifications: [[String: Any]] = subs.map { sub in
                [
                    "type": "Add",
                    "queryId": sub.queryId,
                    "udfPath": canonicalizePath(sub.functionName),
                    "args": [sanitizeArgs(sub.args)],
                    "journal": NSNull(),
                ]
            }
            let newVersion = subs.count
            sendWSMessage([
                "type": "ModifyQuerySet",
                "baseVersion": 0,
                "newVersion": newVersion,
                "modifications": modifications,
            ])
            wsLock.lock()
            wsQuerySetVersion = newVersion
            wsLock.unlock()
        }

        wsLock.lock()
        wsIsConnected = true
        wsReconnectDelay = 1.0
        wsLock.unlock()

        DispatchQueue.main.async { self.isConnected = true }

        wsReceiveTask = Task { [weak self] in
            await self?.wsReceiveLoop()
        }

        setupWakeObserver()
    }

    private func sendAddQuery(queryId: Int, functionName: String, args: [String: Any]) {
        wsLock.lock()
        let base = wsQuerySetVersion
        let next = base + 1
        wsQuerySetVersion = next
        wsLock.unlock()

        sendWSMessage([
            "type": "ModifyQuerySet",
            "baseVersion": base,
            "newVersion": next,
            "modifications": [[
                "type": "Add",
                "queryId": queryId,
                "udfPath": canonicalizePath(functionName),
                "args": [sanitizeArgs(args)],
                "journal": NSNull(),
            ]],
        ])
    }

    private func removeWSSubscription(queryId: Int) {
        wsLock.lock()
        wsActiveSubscriptions.removeValue(forKey: queryId)
        let base = wsQuerySetVersion
        let next = base + 1
        wsQuerySetVersion = next
        let remaining = wsActiveSubscriptions.count
        wsLock.unlock()

        sendWSMessage([
            "type": "ModifyQuerySet",
            "baseVersion": base,
            "newVersion": next,
            "modifications": [["type": "Remove", "queryId": queryId]],
        ])

        if remaining == 0 {
            disconnectWebSocket()
        }
    }

    private func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        wsReceiveTask?.cancel()
        wsReceiveTask = nil
        wsLock.lock()
        wsIsConnected = false
        wsLock.unlock()
        print("🔌 ConvexWS: Disconnected")
    }

    // MARK: - WebSocket I/O

    private func sendWSMessage(_ message: [String: Any]) {
        guard let task = webSocketTask else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            guard let str = String(data: data, encoding: .utf8) else { return }
            task.send(.string(str)) { error in
                if let error = error {
                    print("❌ ConvexWS send: \(error.localizedDescription)")
                }
            }
        } catch {
            print("❌ ConvexWS JSON: \(error)")
        }
    }

    private func wsReceiveLoop() async {
        guard let task = webSocketTask else { return }
        while !Task.isCancelled {
            do {
                let msg = try await task.receive()
                switch msg {
                case .string(let text): handleWSMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { handleWSMessage(text) }
                @unknown default: break
                }
            } catch {
                print("⚠️ ConvexWS: Connection lost: \(error.localizedDescription)")
                wsLock.lock()
                wsIsConnected = false
                let hasSubs = !wsActiveSubscriptions.isEmpty
                wsLock.unlock()
                if hasSubs && !Task.isCancelled { await scheduleReconnect() }
                return
            }
        }
    }

    // MARK: - WebSocket Message Handling

    private func handleWSMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "Transition": handleTransition(json)
        case "Ping": sendWSMessage(["type": "Pong"])
        case "FatalError":
            print("❌ ConvexWS: Server error: \(json["message"] as? String ?? "unknown")")
        default: break
        }
    }

    private func handleTransition(_ json: [String: Any]) {
        if let endVersion = json["endVersion"] as? [String: Any] {
            wsMaxTimestamp = endVersion["ts"]
        }
        guard let modifications = json["modifications"] as? [String: Any] else { return }

        wsLock.lock()
        let subs = wsActiveSubscriptions
        wsLock.unlock()

        for (idStr, modValue) in modifications {
            guard let queryId = Int(idStr),
                  let mod = modValue as? [String: Any],
                  let modType = mod["type"] as? String,
                  let sub = subs[queryId]
            else { continue }

            if modType == "QueryUpdated" {
                DispatchQueue.main.async { sub.handleValue(mod["value"]) }
            } else if modType == "QueryFailed" {
                print("❌ ConvexWS: \(sub.functionName) failed: \(mod["errorMessage"] as? String ?? "")")
            }
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() async {
        wsLock.lock()
        let delay = wsReconnectDelay
        wsReconnectDelay = min(wsReconnectDelay * 2, 30.0)
        wsLock.unlock()

        print("🔄 ConvexWS: Reconnecting in \(String(format: "%.0f", delay))s...")
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled { connectWebSocket() }
        } catch { /* cancelled */ }
    }

    private func setupWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔌 ConvexWS: System wake — reconnecting...")
            self?.connectWebSocket()
        }
    }

    // MARK: - WebSocket Decoding

    private func decodeWSValue<T: Decodable>(_ rawValue: Any?, type: T.Type) throws -> T? {
        if rawValue == nil || rawValue is NSNull { return nil }
        let valueData: Data
        if JSONSerialization.isValidJSONObject(rawValue!) {
            valueData = try JSONSerialization.data(withJSONObject: rawValue!)
        } else {
            let wrapped = [rawValue!]
            let wrappedData = try JSONSerialization.data(withJSONObject: wrapped)
            guard let wrappedStr = String(data: wrappedData, encoding: .utf8),
                  wrappedStr.count > 2 else { throw ConvexError.decodingError }
            let s = wrappedStr.index(wrappedStr.startIndex, offsetBy: 1)
            let e = wrappedStr.index(wrappedStr.endIndex, offsetBy: -1)
            guard let d = String(wrappedStr[s..<e]).data(using: .utf8) else { throw ConvexError.decodingError }
            valueData = d
        }
        return try JSONDecoder().decode(T.self, from: valueData)
    }

    /// Adds .js extension to module path for Convex sync protocol wire format
    private func canonicalizePath(_ path: String) -> String {
        let parts = path.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return path }
        let mod = String(parts[0])
        let fn = String(parts[1])
        if mod.contains(".") { return path }
        return "\(mod).js:\(fn)"
    }

    // MARK: - Helpers

    var isReady: Bool {
        return !deploymentUrl.contains("YOUR_DEPLOYMENT")
    }

    /// Sanitizes a dictionary to ensure all values are JSON-serializable
    private func sanitizeArgs(_ args: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [:]
        for (key, value) in args {
            switch value {
            case let string as String:
                sanitized[key] = string
            case let number as NSNumber:
                sanitized[key] = number
            case let int as Int:
                sanitized[key] = int
            case let double as Double:
                sanitized[key] = double
            case let bool as Bool:
                sanitized[key] = bool
            case let array as [Any]:
                sanitized[key] = sanitizeArray(array)
            case let dict as [String: Any]:
                sanitized[key] = sanitizeArgs(dict)
            case is NSNull:
                sanitized[key] = NSNull()
            default:
                // Convert unknown types to string representation
                sanitized[key] = String(describing: value)
                print("⚠️ ConvexManager: Converting non-JSON type to string for key '\(key)'")
            }
        }
        return sanitized
    }

    private func sanitizeArray(_ array: [Any]) -> [Any] {
        return array.map { element in
            switch element {
            case let string as String:
                return string
            case let number as NSNumber:
                return number
            case let int as Int:
                return int
            case let double as Double:
                return double
            case let bool as Bool:
                return bool
            case let array as [Any]:
                return sanitizeArray(array)
            case let dict as [String: Any]:
                return sanitizeArgs(dict)
            case is NSNull:
                return NSNull()
            default:
                return String(describing: element)
            }
        }
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
