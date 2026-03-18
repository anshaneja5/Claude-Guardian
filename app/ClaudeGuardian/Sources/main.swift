import Cocoa
import SwiftUI

// MARK: - Data Models

struct PermissionRequest: Identifiable, Codable {
    let id: String
    let toolName: String
    let toolInput: [String: AnyCodableValue]
    let sessionId: String
    let timestamp: Double
    var status: RequestStatus = .pending
    var message: String = ""

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case sessionId = "session_id"
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID().uuidString
        self.toolName = try container.decode(String.self, forKey: .toolName)
        self.toolInput = (try? container.decode([String: AnyCodableValue].self, forKey: .toolInput)) ?? [:]
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.timestamp = try container.decode(Double.self, forKey: .timestamp)
    }

    init(id: String, toolName: String, toolInput: [String: AnyCodableValue], sessionId: String, timestamp: Double) {
        self.id = id
        self.toolName = toolName
        self.toolInput = toolInput
        self.sessionId = sessionId
        self.timestamp = timestamp
    }
}

enum RequestStatus: String, Codable {
    case pending, approved, denied, timeout
}

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let i = try? container.decode(Int.self) { self = .int(i) }
        else if let d = try? container.decode(Double.self) { self = .double(d) }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let a = try? container.decode([AnyCodableValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: AnyCodableValue].self) { self = .object(o) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return "\(b)"
        case .array(let a): return a.map { $0.stringValue }.joined(separator: ", ")
        case .object(let o): return o.map { "\($0.key): \($0.value.stringValue)" }.joined(separator: ", ")
        case .null: return "null"
        }
    }
}

struct HistoryEntry: Identifiable {
    let id = UUID()
    let toolName: String
    let summary: String
    let decision: RequestStatus
    let timestamp: Date
}

// MARK: - Guardian Config

struct GuardianConfig: Codable {
    let port: Int
    let timeoutSeconds: Int
    let autoApprove: [String]
    let alwaysBlock: [String]
    let mascot: String

    enum CodingKeys: String, CodingKey {
        case port
        case timeoutSeconds = "timeout_seconds"
        case autoApprove = "auto_approve"
        case alwaysBlock = "always_block"
        case mascot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decode(Int.self, forKey: .port)
        timeoutSeconds = try container.decode(Int.self, forKey: .timeoutSeconds)
        autoApprove = try container.decode([String].self, forKey: .autoApprove)
        alwaysBlock = try container.decode([String].self, forKey: .alwaysBlock)
        mascot = (try? container.decode(String.self, forKey: .mascot)) ?? "claude"
    }

    init(port: Int, timeoutSeconds: Int, autoApprove: [String], alwaysBlock: [String], mascot: String = "claude") {
        self.port = port
        self.timeoutSeconds = timeoutSeconds
        self.autoApprove = autoApprove
        self.alwaysBlock = alwaysBlock
        self.mascot = mascot
    }
}

// MARK: - App State

enum GuardianStatus {
    case idle
    case active
    case pendingPermission
    case justApproved   // transient state for thumbs-up animation
    case justDenied     // transient state for sad animation
}

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentRequest: PermissionRequest?
    @Published var status: GuardianStatus = .idle
    @Published var history: [HistoryEntry] = []
    @Published var countdown: Int = 300
    @Published var showOverlay: Bool = false

    private var decisions: [String: (status: RequestStatus, message: String)] = [:]
    private let lock = NSLock()
    private var countdownTimer: Timer?
    var config: GuardianConfig

    init() {
        let configPath = AppState.configFilePath()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let config = try? JSONDecoder().decode(GuardianConfig.self, from: data) {
            self.config = config
        } else {
            self.config = GuardianConfig(port: 9001, timeoutSeconds: 300, autoApprove: [], alwaysBlock: [], mascot: "claude")
        }
    }

    static func configFilePath() -> String {
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        let nearby = (execDir as NSString).appendingPathComponent("../../guardian.config.json")
        if FileManager.default.fileExists(atPath: (nearby as NSString).standardizingPath) {
            return (nearby as NSString).standardizingPath
        }
        let home = NSHomeDirectory()
        return "\(home)/Desktop/claude anime terminal notifs/claude-guardian/guardian.config.json"
    }

    func submitRequest(_ request: PermissionRequest) -> String {
        lock.lock()
        decisions[request.id] = (status: .pending, message: "")
        lock.unlock()

        DispatchQueue.main.async {
            self.currentRequest = request
            self.status = .pendingPermission
            self.countdown = self.config.timeoutSeconds
            self.showOverlay = true
            self.startCountdown()
        }
        return request.id
    }

    func getDecision(for id: String) -> (status: RequestStatus, message: String)? {
        lock.lock()
        defer { lock.unlock() }
        return decisions[id]
    }

    func approve() {
        guard let req = currentRequest else { return }
        lock.lock()
        decisions[req.id] = (status: .approved, message: "")
        lock.unlock()

        history.insert(HistoryEntry(
            toolName: req.toolName, summary: toolSummary(req),
            decision: .approved, timestamp: Date()
        ), at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }

        stopCountdown()
        showOverlay = false
        currentRequest = nil
        status = .justApproved

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.status == .justApproved { self.status = .idle }
        }
    }

    func deny(message: String = "") {
        guard let req = currentRequest else { return }
        lock.lock()
        decisions[req.id] = (status: .denied, message: message)
        lock.unlock()

        history.insert(HistoryEntry(
            toolName: req.toolName, summary: toolSummary(req),
            decision: .denied, timestamp: Date()
        ), at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }

        stopCountdown()
        showOverlay = false
        currentRequest = nil
        status = .justDenied

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.status == .justDenied { self.status = .idle }
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.countdown -= 1
                if self.countdown <= 0 { self.timeoutRequest() }
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func timeoutRequest() {
        guard let req = currentRequest else { return }
        lock.lock()
        decisions[req.id] = (status: .timeout, message: "Auto-denied: timeout")
        lock.unlock()

        history.insert(HistoryEntry(
            toolName: req.toolName, summary: toolSummary(req),
            decision: .timeout, timestamp: Date()
        ), at: 0)

        stopCountdown()
        showOverlay = false
        currentRequest = nil
        status = .idle
    }

    private func toolSummary(_ req: PermissionRequest) -> String {
        if let cmd = req.toolInput["command"]?.stringValue { return String(cmd.prefix(80)) }
        if let path = req.toolInput["file_path"]?.stringValue { return path }
        if let pattern = req.toolInput["pattern"]?.stringValue { return pattern }
        return req.toolName
    }
}


// MARK: - HTTP Server

import Network

class HTTPServer {
    let port: UInt16
    let listener: NWListener
    let state: AppState

    init(port: UInt16, state: AppState) {
        self.port = port
        self.state = state
        let params = NWParameters.tcp
        self.listener = try! NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: print("Guardian server listening on port \(self.port)")
            case .failed(let err): print("Server failed: \(err)")
            default: break
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        let buffer = Data()
        receiveLoop(connection: connection, buffer: buffer)
    }

    private func receiveLoop(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }
            var buf = buffer
            if let data = data { buf.append(data) }
            let raw = String(data: buf, encoding: .utf8) ?? ""
            let firstLine = raw.prefix(while: { $0 != "\r" && $0 != "\n" })
            let parts = firstLine.split(separator: " ")
            let method = parts.count >= 1 ? String(parts[0]) : ""

            if method == "GET" {
                self.routeRequest(rawRequest: raw, connection: connection)
                return
            }
            if method == "POST" {
                if let headerEnd = raw.range(of: "\r\n\r\n") {
                    let headerSection = String(raw[raw.startIndex..<headerEnd.lowerBound])
                    let bodyStr = String(raw[headerEnd.upperBound...])
                    var contentLength = 0
                    for line in headerSection.split(separator: "\r\n") {
                        if line.lowercased().hasPrefix("content-length:") {
                            contentLength = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
                        }
                    }
                    if bodyStr.utf8.count >= contentLength {
                        self.routeRequest(rawRequest: raw, connection: connection)
                        return
                    }
                }
                if isComplete || error != nil {
                    self.routeRequest(rawRequest: raw, connection: connection)
                } else {
                    self.receiveLoop(connection: connection, buffer: buf)
                }
                return
            }
            self.sendResponse(connection: connection, status: 400, body: #"{"error":"bad method"}"#)
        }
    }

    private func routeRequest(rawRequest: String, connection: NWConnection) {
        let firstLine = rawRequest.prefix(while: { $0 != "\r" && $0 != "\n" })
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: #"{"error":"bad request"}"#)
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])

        if method == "GET" && path == "/health" {
            sendResponse(connection: connection, status: 200, body: #"{"status":"ok"}"#)
        } else if method == "POST" && path == "/request" {
            handlePermissionRequest(rawRequest: rawRequest, connection: connection)
        } else if method == "GET" && path.hasPrefix("/decision/") {
            handleDecisionPoll(requestId: String(path.dropFirst("/decision/".count)), connection: connection)
        } else {
            sendResponse(connection: connection, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    private func handlePermissionRequest(rawRequest: String, connection: NWConnection) {
        guard let bodyRange = rawRequest.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: 400, body: #"{"error":"no body"}"#)
            return
        }
        let bodyString = String(rawRequest[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8),
              let request = try? JSONDecoder().decode(PermissionRequest.self, from: bodyData) else {
            sendResponse(connection: connection, status: 400, body: #"{"error":"invalid json"}"#)
            return
        }
        let requestId = state.submitRequest(request)
        sendResponse(connection: connection, status: 200, body: "{\"request_id\":\"\(requestId)\",\"status\":\"pending\"}")
    }

    private func handleDecisionPoll(requestId: String, connection: NWConnection) {
        if let decision = state.getDecision(for: requestId) {
            let msg = decision.message.replacingOccurrences(of: "\"", with: "\\\"")
            sendResponse(connection: connection, status: 200, body: "{\"status\":\"\(decision.status.rawValue)\",\"message\":\"\(msg)\"}")
        } else {
            sendResponse(connection: connection, status: 404, body: #"{"status":"not_found"}"#)
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }
        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}


// MARK: - Animated Mascot View

let allMascotNames = ["claude", "cat", "owl", "skull", "dog", "dragon"]

struct AnimatedMascot: View {
    let size: CGFloat
    @ObservedObject var appState: AppState
    @State private var frame: Int = 0

    private func sprites() -> (idle1: [[Int]], idle2: [[Int]], idle3: [[Int]], wave1: [[Int]], wave2: [[Int]], happy: [[Int]], sad1: [[Int]], sad2: [[Int]]) {
        switch appState.config.mascot.lowercased() {
        case "cat": return (CatSprites.idle1, CatSprites.idle2, CatSprites.idle3, CatSprites.wave1, CatSprites.wave2, CatSprites.happy, CatSprites.sad1, CatSprites.sad2)
        case "owl": return (OwlSprites.idle1, OwlSprites.idle2, OwlSprites.idle3, OwlSprites.wave1, OwlSprites.wave2, OwlSprites.happy, OwlSprites.sad1, OwlSprites.sad2)
        case "skull": return (SkullSprites.idle1, SkullSprites.idle2, SkullSprites.idle3, SkullSprites.wave1, SkullSprites.wave2, SkullSprites.happy, SkullSprites.sad1, SkullSprites.sad2)
        case "dog": return (DogSprites.idle1, DogSprites.idle2, DogSprites.idle3, DogSprites.wave1, DogSprites.wave2, DogSprites.happy, DogSprites.sad1, DogSprites.sad2)
        case "dragon": return (DragonSprites.idle1, DragonSprites.idle2, DragonSprites.idle3, DragonSprites.wave1, DragonSprites.wave2, DragonSprites.happy, DragonSprites.sad1, DragonSprites.sad2)
        default: return (ClaudeSprites.idle1, ClaudeSprites.idle2, ClaudeSprites.idle3, ClaudeSprites.wave1, ClaudeSprites.wave2, ClaudeSprites.happy, ClaudeSprites.sad1, ClaudeSprites.sad2)
        }
    }

    private func colorFor(_ v: Int) -> Color {
        switch appState.config.mascot.lowercased() {
        case "cat": return CatSprites.color(for: v)
        case "owl": return OwlSprites.color(for: v)
        case "skull": return SkullSprites.color(for: v)
        case "dog": return DogSprites.color(for: v)
        case "dragon": return DragonSprites.color(for: v)
        default: return ClaudeSprites.color(for: v)
        }
    }

    private func currentSprite() -> [[Int]] {
        let s = sprites()
        switch appState.status {
        case .idle:
            let cycle = [0, 0, 2, 0, 0, 1]
            switch cycle[frame % cycle.count] {
            case 1: return s.idle2
            case 2: return s.idle3
            default: return s.idle1
            }
        case .active:
            return frame % 2 == 0 ? s.idle1 : s.idle3
        case .pendingPermission:
            return frame % 2 == 0 ? s.wave1 : s.wave2
        case .justApproved:
            return s.happy
        case .justDenied:
            return frame % 2 == 0 ? s.sad1 : s.sad2
        }
    }

    var body: some View {
        let sprite = currentSprite()
        let cols = sprite.isEmpty ? 16 : sprite[0].count
        let rows = sprite.count
        let pixelSize = size / CGFloat(rows)

        Canvas { context, _ in
            for row in 0..<rows {
                for col in 0..<min(cols, sprite[row].count) {
                    let value = sprite[row][col]
                    if value != 0 {
                        let rect = CGRect(
                            x: CGFloat(col) * pixelSize,
                            y: CGFloat(row) * pixelSize,
                            width: pixelSize + 0.5,
                            height: pixelSize + 0.5
                        )
                        context.fill(Path(rect), with: .color(colorFor(value)))
                    }
                }
            }
        }
        .frame(width: CGFloat(cols) * pixelSize, height: size)
        .onAppear { startAnimationTimer() }
    }

    private func startAnimationTimer() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async { self.frame += 1 }
        }
    }
}

// MARK: - Unified Mascot + Permission Widget

struct UnifiedWidgetView: View {
    @ObservedObject var appState: AppState
    @State private var denyMessage: String = ""
    @State private var showDenyField: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // === Mascot section (always visible) ===
            VStack(spacing: 4) {
                AnimatedMascot(size: 64, appState: appState)

                Text(statusLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(statusLabelColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(statusLabelColor.opacity(0.15)))
            }
            .padding(.top, 10)
            .padding(.bottom, appState.showOverlay ? 8 : 10)
            .frame(maxWidth: .infinity)

            // === Permission panel (expands below mascot when needed) ===
            if appState.showOverlay {
                VStack(alignment: .leading, spacing: 10) {
                    // Divider between mascot and panel
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .padding(.horizontal, 8)

                    // Countdown + title row
                    HStack {
                        Text("Permission Request")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.gray)

                        Spacer()

                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 2.5)
                                .frame(width: 30, height: 30)
                            Circle()
                                .trim(from: 0, to: CGFloat(appState.countdown) / CGFloat(appState.config.timeoutSeconds))
                                .stroke(countdownColor, lineWidth: 2.5)
                                .frame(width: 30, height: 30)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: appState.countdown)
                            Text("\(appState.countdown)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(countdownColor)
                        }
                    }
                    .padding(.horizontal, 12)

                    if let req = appState.currentRequest {
                        // Tool type
                        HStack(spacing: 5) {
                            Text(toolIcon(req.toolName)).font(.system(size: 14))
                            Text(toolDisplayName(req.toolName))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.93, green: 0.45, blue: 0.32))
                        }
                        .padding(.horizontal, 12)

                        // Content
                        let content = toolContent(req)
                        Text(content.isEmpty ? "(no content)" : content)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(red: 0.9, green: 0.95, blue: 1.0))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(red: 0.06, green: 0.06, blue: 0.09))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                    }

                    // Deny message field
                    if showDenyField {
                        TextField("Message to Claude (optional)...", text: $denyMessage)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(5)
                            .padding(.horizontal, 12)
                    }

                    // Buttons
                    HStack(spacing: 10) {
                        Button(action: {
                            if showDenyField {
                                appState.deny(message: denyMessage)
                                denyMessage = ""
                                showDenyField = false
                            } else {
                                showDenyField = true
                            }
                        }) {
                            HStack(spacing: 3) {
                                Text("✕")
                                Text(showDenyField ? "Send & Deny" : "Deny")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.7))
                            .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])

                        Button(action: {
                            appState.approve()
                            showDenyField = false
                            denyMessage = ""
                        }) {
                            HStack(spacing: 3) {
                                Text("✓")
                                Text("Allow")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.green.opacity(0.7))
                            .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: appState.showOverlay ? 340 : 95)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.92))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusBorderColor.opacity(0.4), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: appState.showOverlay)
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch appState.status {
        case .idle: return "IDLE"
        case .active: return "WORKING"
        case .pendingPermission: return "NEEDS YOU"
        case .justApproved: return "APPROVED!"
        case .justDenied: return "DENIED"
        }
    }

    private var statusLabelColor: Color {
        switch appState.status {
        case .idle: return .green
        case .active: return .orange
        case .pendingPermission: return .red
        case .justApproved: return .green
        case .justDenied: return .red
        }
    }

    private var statusBorderColor: Color {
        switch appState.status {
        case .pendingPermission: return .red
        case .justApproved: return .green
        default: return Color(red: 0.93, green: 0.45, blue: 0.32)
        }
    }

    private var countdownColor: Color {
        if appState.countdown > 30 { return .green }
        if appState.countdown > 10 { return .yellow }
        return .red
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Bash": return "⚡"
        case "Write": return "📝"
        case "Edit": return "✏️"
        case "Read": return "📖"
        case "Glob": return "🔍"
        case "Grep": return "🔎"
        default: return "🔧"
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case "Bash": return "Shell Command"
        case "Write": return "Write File"
        case "Edit": return "Edit File"
        case "Read": return "Read File"
        case "Glob": return "File Search"
        case "Grep": return "Content Search"
        default: return name
        }
    }

    private func toolContent(_ req: PermissionRequest) -> String {
        if let cmd = req.toolInput["command"]?.stringValue { return "$ \(cmd)" }
        if let path = req.toolInput["file_path"]?.stringValue {
            var result = path
            if let content = req.toolInput["content"]?.stringValue {
                result += "\n\n" + String(content.prefix(500))
                if content.count > 500 { result += "\n..." }
            }
            if let old = req.toolInput["old_string"]?.stringValue {
                result += "\n\nReplace:\n" + String(old.prefix(200))
                if let new = req.toolInput["new_string"]?.stringValue {
                    result += "\n\nWith:\n" + String(new.prefix(200))
                }
            }
            return result
        }
        if let pattern = req.toolInput["pattern"]?.stringValue { return "Pattern: \(pattern)" }
        return req.toolInput.map { "\($0.key): \($0.value.stringValue)" }.joined(separator: "\n")
    }
}


// MARK: - History View (menubar popover)

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @State private var filter: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AnimatedMascot(size: 32, appState: appState)
                Text("Claude Guardian")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Spacer()
                Circle().fill(statusColor).frame(width: 8, height: 8)
            }
            .padding(.bottom, 4)

            Divider()

            // Filter bar
            HStack(spacing: 4) {
                Text("🔍").font(.system(size: 10))
                TextField("Filter...", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                if !filter.isEmpty {
                    Button(action: { filter = "" }) {
                        Text("✕").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)

            // Stats bar
            HStack(spacing: 12) {
                let approved = appState.history.filter { $0.decision == .approved }.count
                let denied = appState.history.filter { $0.decision == .denied || $0.decision == .timeout }.count
                Text("✓ \(approved)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                Text("✕ \(denied)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                Spacer()
                Text("\(appState.history.count) total")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            if filteredHistory.isEmpty {
                Text(appState.history.isEmpty ? "No recent actions" : "No matching actions")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredHistory.prefix(30)) { entry in
                            HStack(spacing: 6) {
                                Text(entry.decision == .approved ? "✓" : "✕")
                                    .foregroundColor(entry.decision == .approved ? .green : .red)
                                    .font(.system(size: 11, weight: .bold))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.toolName)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    Text(entry.summary)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(timeAgo(entry.timestamp))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            Button("Quit Claude Guardian") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11, design: .monospaced))
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding(12)
        .frame(width: 320)
    }

    private var filteredHistory: [HistoryEntry] {
        if filter.isEmpty { return Array(appState.history) }
        let q = filter.lowercased()
        return appState.history.filter {
            $0.toolName.lowercased().contains(q) || $0.summary.lowercased().contains(q)
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: return .green
        case .active: return .orange
        case .pendingPermission: return .red
        case .justApproved: return .green
        case .justDenied: return .red
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}


// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var widgetWindow: NSWindow!
    var server: HTTPServer!
    let appState = AppState.shared
    var statusAnimationTimer: Timer?
    var lastOverlayState: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupMenubar()
        setupWidgetWindow()
        startServer()
        startStatusAnimation()

        // Poll for overlay state changes to bring window to front + activate keyboard
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let showing = self.appState.showOverlay
            if showing && !self.lastOverlayState {
                // Just became visible — bring to front for keyboard shortcuts
                self.widgetWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            self.lastOverlayState = showing
        }
    }

    private func setupMenubar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🟢"
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HistoryView(appState: appState))
    }

    private func setupWidgetWindow() {
        let widgetView = UnifiedWidgetView(appState: appState)
        let hostingView = NSHostingView(rootView: widgetView)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Start as small mascot in bottom-right
        let widgetX = screenFrame.maxX - 110
        let widgetY = screenFrame.minY + 20

        widgetWindow = NSWindow(
            contentRect: NSRect(x: widgetX, y: widgetY, width: 400, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        widgetWindow.contentView = hostingView
        widgetWindow.isOpaque = false
        widgetWindow.backgroundColor = .clear
        widgetWindow.level = .screenSaver
        widgetWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        widgetWindow.isMovableByWindowBackground = true
        widgetWindow.hasShadow = false  // SwiftUI handles shadows
        widgetWindow.orderFrontRegardless()
    }

    private func startServer() {
        server = HTTPServer(port: UInt16(appState.config.port), state: appState)
        server.start()
    }

    private func startStatusAnimation() {
        statusAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            switch self.appState.status {
            case .idle:
                button.title = "🟢"
            case .active:
                button.title = button.title == "🟠" ? "🔶" : "🟠"
            case .pendingPermission:
                button.title = button.title == "🔴" ? "🔺" : "🔴"
            case .justApproved:
                button.title = "✅"
            case .justDenied:
                button.title = "❌"
            }
        }
    }

    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.contentViewController = NSHostingController(rootView: HistoryView(appState: appState))
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}


// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
