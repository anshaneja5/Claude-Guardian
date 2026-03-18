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
    case string(String), int(Int), double(Double), bool(Bool)
    case array([AnyCodableValue]), object([String: AnyCodableValue]), null

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
    let sessionId: String
    let timestamp: Date
}

// MARK: - Config

struct GuardianConfig: Codable {
    let port: Int
    let timeoutSeconds: Int
    let autoApprove: [String]
    let alwaysBlock: [String]
    let mascot: String

    enum CodingKeys: String, CodingKey {
        case port, mascot
        case timeoutSeconds = "timeout_seconds"
        case autoApprove = "auto_approve"
        case alwaysBlock = "always_block"
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
        self.port = port; self.timeoutSeconds = timeoutSeconds
        self.autoApprove = autoApprove; self.alwaysBlock = alwaysBlock; self.mascot = mascot
    }
}

// MARK: - Per-Session State

enum GuardianStatus {
    case idle, active, pendingPermission, justApproved, justDenied
}

class SessionState: ObservableObject, Identifiable {
    let id: String          // session_id from Claude Code
    let cwd: String         // working directory
    let startedAt: Date

    @Published var status: GuardianStatus = .idle
    @Published var currentRequest: PermissionRequest?
    @Published var countdown: Int = 300
    @Published var showOverlay: Bool = false
    @Published var mascotName: String
    @Published var costUsd: Double = 0.0
    @Published var terminalPid: Int = 0      // PID of the terminal app
    @Published var terminalApp: String = ""   // e.g. "Terminal", "iTerm2", "Ghostty"

    var countdownTimer: Timer?

    init(id: String, cwd: String, timeout: Int, mascot: String) {
        self.id = id
        self.cwd = cwd
        self.startedAt = Date()
        self.countdown = timeout
        self.mascotName = mascot
    }

    func cycleMascot() {
        let names = allMascotNames
        if let idx = names.firstIndex(of: mascotName) {
            mascotName = names[(idx + 1) % names.count]
        } else {
            mascotName = names[0]
        }
    }

    func focusTerminal() {
        guard terminalPid > 0 else { return }
        if let app = NSRunningApplication(processIdentifier: pid_t(terminalPid)) {
            app.activate()
        }
    }

    var costDisplay: String {
        if costUsd < 0.001 { return "" }
        if costUsd < 0.01 { return String(format: "$%.3f", costUsd) }
        return String(format: "$%.2f", costUsd)
    }

    var shortId: String { String(id.prefix(8)) }
    var shortCwd: String {
        let parts = cwd.split(separator: "/")
        return parts.last.map(String.init) ?? cwd
    }
}

// MARK: - Global App State

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var sessions: [SessionState] = []
    @Published var history: [HistoryEntry] = []

    private var decisions: [String: (status: RequestStatus, message: String)] = [:]
    private let lock = NSLock()
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

    // MARK: Session lifecycle

    func sessionStarted(sessionId: String, cwd: String) {
        DispatchQueue.main.async {
            guard !self.sessions.contains(where: { $0.id == sessionId }) else { return }
            let session = SessionState(id: sessionId, cwd: cwd, timeout: self.config.timeoutSeconds, mascot: self.config.mascot)
            self.sessions.append(session)
        }
    }

    func sessionEnded(sessionId: String) {
        DispatchQueue.main.async {
            // If there's a pending request, auto-deny it
            if let session = self.sessions.first(where: { $0.id == sessionId }),
               let req = session.currentRequest {
                self.lock.lock()
                self.decisions[req.id] = (status: .denied, message: "Session ended")
                self.lock.unlock()
                session.countdownTimer?.invalidate()
            }
            self.sessions.removeAll { $0.id == sessionId }
        }
    }

    func getOrCreateSession(sessionId: String) -> SessionState {
        if let existing = sessions.first(where: { $0.id == sessionId }) {
            return existing
        }
        let session = SessionState(id: sessionId, cwd: "", timeout: config.timeoutSeconds, mascot: config.mascot)
        DispatchQueue.main.async {
            self.sessions.append(session)
        }
        return session
    }

    // MARK: Permission flow

    func submitRequest(_ request: PermissionRequest) -> String {
        lock.lock()
        decisions[request.id] = (status: .pending, message: "")
        lock.unlock()

        DispatchQueue.main.async {
            let session = self.getOrCreateSession(sessionId: request.sessionId)
            session.currentRequest = request
            session.status = .pendingPermission
            session.countdown = self.config.timeoutSeconds
            session.showOverlay = true
            self.startCountdown(for: session)
        }
        return request.id
    }

    func getDecision(for id: String) -> (status: RequestStatus, message: String)? {
        lock.lock()
        defer { lock.unlock() }
        return decisions[id]
    }

    func approve(session: SessionState) {
        guard let req = session.currentRequest else { return }
        lock.lock()
        decisions[req.id] = (status: .approved, message: "")
        lock.unlock()

        history.insert(HistoryEntry(
            toolName: req.toolName, summary: toolSummary(req),
            decision: .approved, sessionId: req.sessionId, timestamp: Date()
        ), at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }

        session.countdownTimer?.invalidate()
        session.showOverlay = false
        session.currentRequest = nil
        session.status = .justApproved

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if session.status == .justApproved { session.status = .idle }
        }
    }

    func deny(session: SessionState, message: String = "") {
        guard let req = session.currentRequest else { return }
        lock.lock()
        decisions[req.id] = (status: .denied, message: message)
        lock.unlock()

        history.insert(HistoryEntry(
            toolName: req.toolName, summary: toolSummary(req),
            decision: .denied, sessionId: req.sessionId, timestamp: Date()
        ), at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }

        session.countdownTimer?.invalidate()
        session.showOverlay = false
        session.currentRequest = nil
        session.status = .justDenied

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if session.status == .justDenied { session.status = .idle }
        }
    }

    private func startCountdown(for session: SessionState) {
        session.countdownTimer?.invalidate()
        session.countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak session] _ in
            guard let self = self, let session = session else { return }
            DispatchQueue.main.async {
                session.countdown -= 1
                if session.countdown <= 0 { self.timeoutRequest(for: session) }
            }
        }
    }

    private func timeoutRequest(for session: SessionState) {
        guard let req = session.currentRequest else { return }
        lock.lock()
        decisions[req.id] = (status: .timeout, message: "Auto-denied: timeout")
        lock.unlock()

        history.insert(HistoryEntry(
            toolName: req.toolName, summary: toolSummary(req),
            decision: .timeout, sessionId: req.sessionId, timestamp: Date()
        ), at: 0)

        session.countdownTimer?.invalidate()
        session.showOverlay = false
        session.currentRequest = nil
        session.status = .idle
    }

    private func toolSummary(_ req: PermissionRequest) -> String {
        if let cmd = req.toolInput["command"]?.stringValue { return String(cmd.prefix(80)) }
        if let path = req.toolInput["file_path"]?.stringValue { return path }
        if let pattern = req.toolInput["pattern"]?.stringValue { return pattern }
        return req.toolName
    }

    // Aggregate status for menubar
    var overallStatus: GuardianStatus {
        if sessions.contains(where: { $0.status == .pendingPermission }) { return .pendingPermission }
        if sessions.contains(where: { $0.status == .justApproved }) { return .justApproved }
        if sessions.contains(where: { $0.status == .justDenied }) { return .justDenied }
        if !sessions.isEmpty { return .active }
        return .idle
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
        } else if method == "POST" && path == "/session" {
            handleSessionEvent(rawRequest: rawRequest, connection: connection)
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

    private func handleSessionEvent(rawRequest: String, connection: NWConnection) {
        guard let bodyRange = rawRequest.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: 400, body: #"{"error":"no body"}"#)
            return
        }
        let bodyString = String(rawRequest[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: #"{"error":"invalid json"}"#)
            return
        }

        let event = json["event"] as? String ?? ""
        let sessionId = json["session_id"] as? String ?? "unknown"
        let cwd = json["cwd"] as? String ?? ""
        let terminalPid = json["terminal_pid"] as? Int ?? 0
        let terminalApp = json["terminal_app"] as? String ?? ""

        if event == "SessionStart" {
            state.sessionStarted(sessionId: sessionId, cwd: cwd)
            // Update terminal info
            DispatchQueue.main.async {
                if let session = self.state.sessions.first(where: { $0.id == sessionId }) {
                    session.terminalPid = terminalPid
                    session.terminalApp = terminalApp
                }
            }
        } else if event == "SessionEnd" {
            state.sessionEnded(sessionId: sessionId)
        } else if event == "CostUpdate" {
            let costUsd = json["cost_usd"] as? Double ?? 0
            DispatchQueue.main.async {
                if let session = self.state.sessions.first(where: { $0.id == sessionId }) {
                    session.costUsd = costUsd
                }
            }
        }

        sendResponse(connection: connection, status: 200, body: #"{"status":"ok"}"#)
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
    let status: GuardianStatus
    let mascotName: String
    @State private var frame: Int = 0

    private func sprites() -> (idle1: [[Int]], idle2: [[Int]], idle3: [[Int]], wave1: [[Int]], wave2: [[Int]], happy: [[Int]], sad1: [[Int]], sad2: [[Int]]) {
        switch mascotName.lowercased() {
        case "cat": return (CatSprites.idle1, CatSprites.idle2, CatSprites.idle3, CatSprites.wave1, CatSprites.wave2, CatSprites.happy, CatSprites.sad1, CatSprites.sad2)
        case "owl": return (OwlSprites.idle1, OwlSprites.idle2, OwlSprites.idle3, OwlSprites.wave1, OwlSprites.wave2, OwlSprites.happy, OwlSprites.sad1, OwlSprites.sad2)
        case "skull": return (SkullSprites.idle1, SkullSprites.idle2, SkullSprites.idle3, SkullSprites.wave1, SkullSprites.wave2, SkullSprites.happy, SkullSprites.sad1, SkullSprites.sad2)
        case "dog": return (DogSprites.idle1, DogSprites.idle2, DogSprites.idle3, DogSprites.wave1, DogSprites.wave2, DogSprites.happy, DogSprites.sad1, DogSprites.sad2)
        case "dragon": return (DragonSprites.idle1, DragonSprites.idle2, DragonSprites.idle3, DragonSprites.wave1, DragonSprites.wave2, DragonSprites.happy, DragonSprites.sad1, DragonSprites.sad2)
        default: return (ClaudeSprites.idle1, ClaudeSprites.idle2, ClaudeSprites.idle3, ClaudeSprites.wave1, ClaudeSprites.wave2, ClaudeSprites.happy, ClaudeSprites.sad1, ClaudeSprites.sad2)
        }
    }

    private func colorFor(_ v: Int) -> Color {
        switch mascotName.lowercased() {
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
        switch status {
        case .idle:
            let cycle = [0, 0, 2, 0, 0, 1]
            switch cycle[frame % cycle.count] {
            case 1: return s.idle2; case 2: return s.idle3; default: return s.idle1
            }
        case .active: return frame % 2 == 0 ? s.idle1 : s.idle3
        case .pendingPermission: return frame % 2 == 0 ? s.wave1 : s.wave2
        case .justApproved: return s.happy
        case .justDenied: return frame % 2 == 0 ? s.sad1 : s.sad2
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
                            x: CGFloat(col) * pixelSize, y: CGFloat(row) * pixelSize,
                            width: pixelSize + 0.5, height: pixelSize + 0.5
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


// MARK: - Per-Session Widget

struct SessionWidgetView: View {
    @ObservedObject var session: SessionState
    @ObservedObject var appState: AppState
    @State private var denyMessage: String = ""
    @State private var showDenyField: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // === Mascot + session label ===
            VStack(spacing: 3) {
                AnimatedMascot(size: 52, status: session.status, mascotName: session.mascotName)
                    .onTapGesture { session.focusTerminal() }
                    .onLongPressGesture(minimumDuration: 0.5) { session.cycleMascot() }
                    .help("Click: jump to terminal | Hold: change mascot")

                // Session label
                HStack(spacing: 3) {
                    Text(session.shortCwd.isEmpty ? session.shortId : session.shortCwd)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)

                    if !session.costDisplay.isEmpty {
                        Text(session.costDisplay)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }

                Text(statusLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(statusLabelColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(statusLabelColor.opacity(0.15)))
            }
            .padding(.top, 8)
            .padding(.bottom, session.showOverlay ? 6 : 8)
            .frame(maxWidth: .infinity)

            // === Permission panel ===
            if session.showOverlay {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1).padding(.horizontal, 8)

                    HStack {
                        Text("Permission Request")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        ZStack {
                            Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2).frame(width: 26, height: 26)
                            Circle()
                                .trim(from: 0, to: CGFloat(session.countdown) / CGFloat(appState.config.timeoutSeconds))
                                .stroke(countdownColor, lineWidth: 2)
                                .frame(width: 26, height: 26)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: session.countdown)
                            Text("\(session.countdown)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(countdownColor)
                        }
                    }
                    .padding(.horizontal, 10)

                    if let req = session.currentRequest {
                        HStack(spacing: 4) {
                            Text(toolIcon(req.toolName)).font(.system(size: 12))
                            Text(toolDisplayName(req.toolName))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.93, green: 0.45, blue: 0.32))
                        }
                        .padding(.horizontal, 10)

                        let content = toolContent(req)
                        Text(content.isEmpty ? "(no content)" : content)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(red: 0.9, green: 0.95, blue: 1.0))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7)
                            .background(Color(red: 0.06, green: 0.06, blue: 0.09))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                    }

                    if showDenyField {
                        TextField("Message (optional)...", text: $denyMessage)
                            .textFieldStyle(.plain)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(4)
                            .padding(.horizontal, 10)
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            if showDenyField {
                                appState.deny(session: session, message: denyMessage)
                                denyMessage = ""; showDenyField = false
                            } else { showDenyField = true }
                        }) {
                            HStack(spacing: 2) {
                                Text("✕"); Text(showDenyField ? "Send & Deny" : "Deny")
                            }
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(Color.red.opacity(0.7)).cornerRadius(6)
                        }.buttonStyle(.plain)

                        Button(action: {
                            appState.approve(session: session)
                            showDenyField = false; denyMessage = ""
                        }) {
                            HStack(spacing: 2) {
                                Text("✓"); Text("Allow")
                            }
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(Color.green.opacity(0.7)).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: session.showOverlay ? 320 : 85)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusBorderColor.opacity(0.4), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: session.showOverlay)
    }

    private var statusLabel: String {
        switch session.status {
        case .idle: return "IDLE"
        case .active: return "WORKING"
        case .pendingPermission: return "NEEDS YOU"
        case .justApproved: return "APPROVED!"
        case .justDenied: return "DENIED"
        }
    }
    private var statusLabelColor: Color {
        switch session.status {
        case .idle: return .green; case .active: return .orange
        case .pendingPermission: return .red; case .justApproved: return .green; case .justDenied: return .red
        }
    }
    private var statusBorderColor: Color {
        switch session.status {
        case .pendingPermission: return .red; case .justApproved: return .green
        default: return Color(red: 0.93, green: 0.45, blue: 0.32)
        }
    }
    private var countdownColor: Color {
        if session.countdown > 30 { return .green }; if session.countdown > 10 { return .yellow }; return .red
    }
    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Bash": return "⚡"; case "Write": return "📝"; case "Edit": return "✏️"
        case "Read": return "📖"; case "Glob": return "🔍"; case "Grep": return "🔎"; default: return "🔧"
        }
    }
    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case "Bash": return "Shell Command"; case "Write": return "Write File"; case "Edit": return "Edit File"
        case "Read": return "Read File"; case "Glob": return "File Search"; case "Grep": return "Content Search"; default: return name
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


// (Each session gets its own NSWindow — no stacking container needed)


// MARK: - History View (menubar popover)

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @State private var filter: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude Guardian")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(appState.sessions.count) session\(appState.sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

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

            HStack(spacing: 12) {
                let approved = appState.history.filter { $0.decision == .approved }.count
                let denied = appState.history.filter { $0.decision == .denied || $0.decision == .timeout }.count
                Text("✓ \(approved)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.green)
                Text("✕ \(denied)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.red)
                Spacer()
                Text("\(appState.history.count) total").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
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
    var server: HTTPServer!
    let appState = AppState.shared
    var statusAnimationTimer: Timer?
    var sessionWindows: [String: NSWindow] = [:]  // session_id -> window
    var windowCounter: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupMenubar()
        startServer()
        startStatusAnimation()

        // Poll for session changes: create/remove windows, activate when needed
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.syncSessionWindows()
        }
    }

    private func syncSessionWindows() {
        let currentIds = Set(appState.sessions.map { $0.id })
        let windowIds = Set(sessionWindows.keys)

        // Create windows for new sessions
        for session in appState.sessions {
            if !windowIds.contains(session.id) {
                createWindowForSession(session)
            }
        }

        // Remove windows for ended sessions
        for id in windowIds {
            if !currentIds.contains(id) {
                sessionWindows[id]?.orderOut(nil)
                sessionWindows.removeValue(forKey: id)
            }
        }

        // Bring pending sessions to front
        for session in appState.sessions {
            if session.showOverlay, let window = sessionWindows[session.id] {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func createWindowForSession(_ session: SessionState) {
        let widgetView = SessionWidgetView(session: session, appState: appState)
        let hostingView = NSHostingView(rootView: widgetView)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Offset each new window so they don't stack exactly on top of each other
        let offset = CGFloat(windowCounter % 3) * 110
        let widgetX = screenFrame.maxX - 110 - offset
        let widgetY = screenFrame.minY + 20

        let window = NSWindow(
            contentRect: NSRect(x: widgetX, y: widgetY, width: 400, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.hasShadow = false
        window.orderFrontRegardless()

        sessionWindows[session.id] = window
        windowCounter += 1
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

    private func startServer() {
        server = HTTPServer(port: UInt16(appState.config.port), state: appState)
        server.start()
    }

    private func startStatusAnimation() {
        statusAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            let status = self.appState.overallStatus
            switch status {
            case .idle: button.title = "🟢"
            case .active: button.title = button.title == "🟠" ? "🔶" : "🟠"
            case .pendingPermission: button.title = button.title == "🔴" ? "🔺" : "🔴"
            case .justApproved: button.title = "✅"
            case .justDenied: button.title = "❌"
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
