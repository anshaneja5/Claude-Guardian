// ClaudeAnalytics.swift
// Integrates ClaudeWatch analytics into ClaudeGuardian (no SwiftData, no SwiftPM, macOS only)

import Foundation
import Cocoa

// MARK: - Data Models (plain Swift structs, no @Model)

struct AnalyticsSessionRecord: Identifiable {
    var id: String { sessionId }
    var sessionId: String = ""
    var projectName: String = ""
    var projectPath: String = ""
    var startTime: Date = Date()
    var durationMinutes: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var costUSD: Double = 0
    var messageCount: Int = 0
    var toolCallCount: Int = 0
    var modelName: String = ""
    var summary: String = ""
    var firstPrompt: String = ""

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var formattedCost: String { String(format: "$%.2f", costUSD) }

    var formattedDuration: String {
        let totalMinutes = Int(durationMinutes)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

struct AnalyticsDailyStats: Identifiable {
    var id: String { dateString }
    var date: Date = Date()
    var dateString: String = ""
    var sessionCount: Int = 0
    var messageCount: Int = 0
    var toolCallCount: Int = 0
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCacheCreationTokens: Int = 0
    var totalCacheReadTokens: Int = 0
    var totalCostUSD: Double = 0

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens + totalCacheCreationTokens + totalCacheReadTokens
    }

    var formattedCost: String { String(format: "$%.2f", totalCostUSD) }

    static func makeDateString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}

struct AnalyticsUsageLimitsRecord: Identifiable {
    var id = UUID()
    var fiveHourPercent: Double = 0
    var sevenDayPercent: Double = 0
    var fiveHourResetsAt: Date? = nil
    var sevenDayResetsAt: Date? = nil
    var lastUpdated: Date = Date()

    var fiveHourFraction: Double { fiveHourPercent / 100.0 }
    var sevenDayFraction: Double { sevenDayPercent / 100.0 }
    var fiveHourFormatted: String { String(format: "%.1f%%", fiveHourPercent) }
    var sevenDayFormatted: String { String(format: "%.1f%%", sevenDayPercent) }

    var fiveHourTimeRemaining: String? {
        guard let reset = fiveHourResetsAt else { return nil }
        let seconds = reset.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "< 1m"
    }

    var sevenDayTimeRemaining: String? {
        guard let reset = sevenDayResetsAt else { return nil }
        let seconds = reset.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "< 1m"
    }
}

// MARK: - JSONLParser Data Models

struct AnalyticsJSONLEntry: Codable {
    let type: String
    let timestamp: String
    let sessionId: String
    let version: String?
    let requestId: String?
    let costUSD: Double?
    let message: AnalyticsAssistantMessage?

    enum CodingKeys: String, CodingKey {
        case type, timestamp, version, message
        case sessionId = "sessionId"
        case requestId = "requestId"
        case costUSD = "costUSD"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        type = (try? container.decode(String.self, forKey: DynamicCodingKeys("type"))) ?? ""
        timestamp = (try? container.decode(String.self, forKey: DynamicCodingKeys("timestamp"))) ?? ""
        sessionId = (try? container.decode(String.self, forKey: DynamicCodingKeys("sessionId")))
            ?? (try? container.decode(String.self, forKey: DynamicCodingKeys("session_id"))) ?? ""
        version = try? container.decode(String.self, forKey: DynamicCodingKeys("version"))
        requestId = (try? container.decode(String.self, forKey: DynamicCodingKeys("requestId")))
            ?? (try? container.decode(String.self, forKey: DynamicCodingKeys("request_id")))
        costUSD = (try? container.decode(Double.self, forKey: DynamicCodingKeys("costUSD")))
            ?? (try? container.decode(Double.self, forKey: DynamicCodingKeys("cost_usd")))
        message = try? container.decode(AnalyticsAssistantMessage.self, forKey: DynamicCodingKeys("message"))
    }

    func encode(to encoder: Encoder) throws {}
}

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

struct AnalyticsAssistantMessage: Codable {
    let id: String?
    let model: String?
    let usage: AnalyticsTokenUsageRaw?
}

struct AnalyticsTokenUsageRaw: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - TokenUsage

struct AnalyticsTokenUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0
    var cacheReadInputTokens: Int = 0

    init(inputTokens: Int = 0, outputTokens: Int = 0,
         cacheCreationInputTokens: Int = 0, cacheReadInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    init(raw: AnalyticsTokenUsageRaw) {
        self.inputTokens = raw.inputTokens
        self.outputTokens = raw.outputTokens
        self.cacheCreationInputTokens = raw.cacheCreationInputTokens ?? 0
        self.cacheReadInputTokens = raw.cacheReadInputTokens ?? 0
    }

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens }

    static func + (lhs: AnalyticsTokenUsage, rhs: AnalyticsTokenUsage) -> AnalyticsTokenUsage {
        AnalyticsTokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheCreationInputTokens: lhs.cacheCreationInputTokens + rhs.cacheCreationInputTokens,
            cacheReadInputTokens: lhs.cacheReadInputTokens + rhs.cacheReadInputTokens
        )
    }

    static func += (lhs: inout AnalyticsTokenUsage, rhs: AnalyticsTokenUsage) { lhs = lhs + rhs }
}

// MARK: - Model Pricing

struct AnalyticsModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheCreationPerMillion: Double
    let cacheReadPerMillion: Double

    static let sonnet = AnalyticsModelPricing(inputPerMillion: 3.00, outputPerMillion: 15.00,
                                               cacheCreationPerMillion: 3.75, cacheReadPerMillion: 0.30)
    static let opus   = AnalyticsModelPricing(inputPerMillion: 15.00, outputPerMillion: 75.00,
                                               cacheCreationPerMillion: 18.75, cacheReadPerMillion: 1.50)
    static let haiku  = AnalyticsModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.00,
                                               cacheCreationPerMillion: 1.00, cacheReadPerMillion: 0.08)

    func totalCost(for usage: AnalyticsTokenUsage) -> Double {
        let m = 1_000_000.0
        return (Double(usage.inputTokens) / m * inputPerMillion)
             + (Double(usage.outputTokens) / m * outputPerMillion)
             + (Double(usage.cacheCreationInputTokens) / m * cacheCreationPerMillion)
             + (Double(usage.cacheReadInputTokens) / m * cacheReadPerMillion)
    }
}

// MARK: - CostCalculator

final class AnalyticsCostCalculator {
    private init() {}

    static func cost(for model: String, usage: AnalyticsTokenUsage) -> Double {
        pricingForModel(model).totalCost(for: usage)
    }

    static func pricingForModel(_ model: String) -> AnalyticsModelPricing {
        let lower = model.lowercased()
        if lower.contains("opus")  { return .opus }
        if lower.contains("haiku") { return .haiku }
        return .sonnet
    }
}

// MARK: - JSONLParser

final class AnalyticsJSONLParser {
    private init() {}

    static func parseSessionFile(at url: URL) -> [AnalyticsJSONLEntry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var results: [AnalyticsJSONLEntry] = []
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let entry = try? decoder.decode(AnalyticsJSONLEntry.self, from: data),
                  entry.type == "assistant",
                  entry.message?.usage != nil else { continue }
            results.append(entry)
        }
        return results
    }

    static func findAllSessionFiles() -> [URL] {
        let root = claudeProjectsDirectory()
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" { files.append(fileURL) }
        }
        return files
    }

    static func extractProjectName(from url: URL) -> String {
        let components = url.pathComponents
        for i in components.indices.dropLast(2) {
            if components[i] == "projects" {
                let folder = components[i + 1]
                let parts = folder.components(separatedBy: "-").filter { !$0.isEmpty }
                return parts.last ?? folder
            }
        }
        return url.deletingLastPathComponent().lastPathComponent
    }

    private static func claudeProjectsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }
}

// MARK: - SessionMetaParser

struct AnalyticsSessionMeta: Codable {
    let sessionId: String
    let projectPath: String?
    let startTime: String?
    let durationMinutes: Double?
    let userMessageCount: Int?
    let assistantMessageCount: Int?
    let toolCounts: [String: Int]?
    let inputTokens: Int?
    let outputTokens: Int?
    let firstPrompt: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case projectPath = "project_path"
        case startTime = "start_time"
        case durationMinutes = "duration_minutes"
        case userMessageCount = "user_message_count"
        case assistantMessageCount = "assistant_message_count"
        case toolCounts = "tool_counts"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case firstPrompt = "first_prompt"
        case summary
    }
}

final class AnalyticsSessionMetaParser {
    private init() {}

    static func loadMeta(sessionId: String) -> AnalyticsSessionMeta? {
        let url = sessionMetaDirectory()
            .appendingPathComponent(sessionId)
            .appendingPathExtension("json")
        return parse(at: url)
    }

    static func loadAllMeta() -> [AnalyticsSessionMeta] {
        let dir = sessionMetaDirectory()
        guard FileManager.default.fileExists(atPath: dir.path),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ) else { return [] }
        return contents.filter { $0.pathExtension == "json" }.compactMap { parse(at: $0) }
    }

    private static func parse(at url: URL) -> AnalyticsSessionMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AnalyticsSessionMeta.self, from: data)
    }

    private static func sessionMetaDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("usage-data")
            .appendingPathComponent("session-meta")
    }
}

// MARK: - UsageLimitsParser

struct AnalyticsRawUsageLimits: Codable {
    let data: AnalyticsRawUsageLimitsData
    let expiresAt: Int?
    enum CodingKeys: String, CodingKey {
        case data
        case expiresAt = "expires_at"
    }
}

struct AnalyticsRawUsageLimitsData: Codable {
    let fiveHourPct: Double?
    let sevenDayPct: Double?
    let fiveHourResetsAt: String?
    let sevenDayResetsAt: String?
    enum CodingKeys: String, CodingKey {
        case fiveHourPct = "five_hour_pct"
        case sevenDayPct = "seven_day_pct"
        case fiveHourResetsAt = "five_hour_resets_at"
        case sevenDayResetsAt = "seven_day_resets_at"
    }
}

final class AnalyticsUsageLimitsParser {
    private init() {}

    static func loadLatestSnapshot() -> AnalyticsRawUsageLimits? {
        let files = findAllUsageLimitFiles()
        let sorted = files.sorted { a, b in
            let dateA = modDate(a) ?? .distantPast
            let dateB = modDate(b) ?? .distantPast
            return dateA > dateB
        }
        for url in sorted {
            if let snapshot = parse(at: url) { return snapshot }
        }
        return nil
    }

    static func findAllUsageLimitFiles() -> [URL] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")

        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.isEmpty && fileURL.lastPathComponent.hasSuffix("-usage-limits") {
                results.append(fileURL)
            }
        }
        return results
    }

    private static func parse(at url: URL) -> AnalyticsRawUsageLimits? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AnalyticsRawUsageLimits.self, from: data)
    }

    private static func modDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

// MARK: - Parsed Intermediate Models

struct AnalyticsParsedSession {
    let sessionId: String
    let projectName: String
    let startTime: Date?
    let durationMinutes: Double?
    let tokenUsage: AnalyticsTokenUsage
    let costUSD: Double
    let messageCount: Int
    let toolCallCount: Int
    let model: String
    let summary: String?
    let firstPrompt: String?
}

struct AnalyticsParsedDailyStats {
    let date: Date
    let dateString: String
    let sessionCount: Int
    let totalTokenUsage: AnalyticsTokenUsage
    let totalCostUSD: Double
    let totalMessages: Int
    let totalToolCalls: Int
}

struct AnalyticsParsedUsageLimits {
    let fiveHourPct: Double
    let sevenDayPct: Double
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
}

// MARK: - ClaudeDataService

final class AnalyticsDataService {

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoWhole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func loadAllSessions() -> [AnalyticsParsedSession] {
        let files = AnalyticsJSONLParser.findAllSessionFiles()
        var entriesBySession: [String: (projectName: String, entries: [AnalyticsJSONLEntry])] = [:]

        for url in files {
            let entries = AnalyticsJSONLParser.parseSessionFile(at: url)
            let project = AnalyticsJSONLParser.extractProjectName(from: url)
            for entry in entries {
                let sid = entry.sessionId
                if entriesBySession[sid] == nil {
                    entriesBySession[sid] = (project, [])
                }
                entriesBySession[sid]?.entries.append(entry)
            }
        }

        return entriesBySession.map { (sid, value) in
            buildSession(sessionId: sid, projectName: value.projectName, entries: value.entries)
        }.sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
    }

    func loadLatestUsageLimits() -> AnalyticsParsedUsageLimits? {
        guard let snapshot = AnalyticsUsageLimitsParser.loadLatestSnapshot() else { return nil }
        return AnalyticsParsedUsageLimits(
            fiveHourPct: snapshot.data.fiveHourPct ?? 0,
            sevenDayPct: snapshot.data.sevenDayPct ?? 0,
            fiveHourResetsAt: snapshot.data.fiveHourResetsAt.flatMap { parseDate($0) },
            sevenDayResetsAt: snapshot.data.sevenDayResetsAt.flatMap { parseDate($0) }
        )
    }

    func loadDailyStats() -> [AnalyticsParsedDailyStats] {
        let sessions = loadAllSessions()
        let calendar = Calendar.current
        var byDay: [String: [AnalyticsParsedSession]] = [:]

        for session in sessions {
            guard let start = session.startTime else { continue }
            let key = AnalyticsDailyStats.makeDateString(from: start)
            byDay[key, default: []].append(session)
        }

        return byDay.map { (dateString, daySessions) in
            var tokens = AnalyticsTokenUsage()
            var cost = 0.0
            var messages = 0
            var tools = 0
            for s in daySessions {
                tokens += s.tokenUsage
                cost += s.costUSD
                messages += s.messageCount
                tools += s.toolCallCount
            }
            let date = calendar.date(from: calendar.dateComponents([.year, .month, .day],
                from: daySessions.first?.startTime ?? Date())) ?? Date()
            return AnalyticsParsedDailyStats(
                date: date, dateString: dateString,
                sessionCount: daySessions.count,
                totalTokenUsage: tokens, totalCostUSD: cost,
                totalMessages: messages, totalToolCalls: tools
            )
        }.sorted { $0.dateString < $1.dateString }
    }

    private func buildSession(sessionId: String, projectName: String,
                               entries: [AnalyticsJSONLEntry]) -> AnalyticsParsedSession {
        var totalUsage = AnalyticsTokenUsage()
        var totalCost = 0.0
        var latestModel = "unknown"
        var earliestTime: Date?

        for entry in entries {
            if let raw = entry.message?.usage {
                totalUsage += AnalyticsTokenUsage(raw: raw)
                if let c = entry.costUSD { totalCost += c }
            }
            if let model = entry.message?.model, !model.isEmpty { latestModel = model }
            if let ts = parseDate(entry.timestamp) {
                if earliestTime == nil || ts < earliestTime! { earliestTime = ts }
            }
        }

        if totalCost == 0 {
            totalCost = AnalyticsCostCalculator.cost(for: latestModel, usage: totalUsage)
        }

        let meta = AnalyticsSessionMetaParser.loadMeta(sessionId: sessionId)
        let startTime = meta?.startTime.flatMap { parseDate($0) } ?? earliestTime
        let messageCount = (meta?.userMessageCount ?? 0) + (meta?.assistantMessageCount ?? entries.count)
        let toolCallCount = meta?.toolCounts?.values.reduce(0, +) ?? 0
        let displayProject = meta?.projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? projectName

        return AnalyticsParsedSession(
            sessionId: sessionId, projectName: displayProject,
            startTime: startTime, durationMinutes: meta?.durationMinutes,
            tokenUsage: totalUsage, costUSD: totalCost,
            messageCount: messageCount, toolCallCount: toolCallCount,
            model: latestModel, summary: meta?.summary, firstPrompt: meta?.firstPrompt
        )
    }

    private func parseDate(_ string: String) -> Date? {
        AnalyticsDataService.isoFractional.date(from: string)
            ?? AnalyticsDataService.isoWhole.date(from: string)
    }
}

// MARK: - FileWatcher (POSIX, no SwiftData)

final class AnalyticsFileWatcher {

    let watchedURL: URL
    var debounceInterval: TimeInterval = 2.0
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.claudeguardian.analytics.filewatcher", qos: .utility)
    private var debounceWork: DispatchWorkItem?

    init(url: URL? = nil) {
        self.watchedURL = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    deinit { stop() }

    func start() {
        guard source == nil else { return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: watchedURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            print("[AnalyticsFileWatcher] Directory not found: \(watchedURL.path)")
            return
        }

        let fd = open(watchedURL.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[AnalyticsFileWatcher] Failed to open fd — errno \(errno)")
            return
        }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )

        src.setEventHandler { [weak self] in self?.scheduleDebounce() }
        src.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source = src
        src.resume()
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        source?.cancel()
        source = nil
    }

    private func scheduleDebounce() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.onChange?() }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}

// MARK: - ClaudeAnalyticsStore (ObservableObject, in-memory, replaces SwiftData)

@MainActor
final class ClaudeAnalyticsStore: ObservableObject {

    static let shared = ClaudeAnalyticsStore()

    @Published var sessions: [AnalyticsSessionRecord] = []
    @Published var dailyStats: [AnalyticsDailyStats] = []
    @Published var usageLimits: AnalyticsUsageLimitsRecord? = nil
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date? = nil

    private let fileWatcher = AnalyticsFileWatcher()
    private var isWatching = false

    private init() {}

    // MARK: - Public API

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true

        let dataService = AnalyticsDataService()

        let rawSessions = await Task.detached(priority: .utility) {
            dataService.loadAllSessions()
        }.value

        let rawLimits = await Task.detached(priority: .utility) {
            dataService.loadLatestUsageLimits()
        }.value

        let rawDailyStats = await Task.detached(priority: .utility) {
            dataService.loadDailyStats()
        }.value

        // Map to in-memory records
        sessions = rawSessions.map { raw in
            var r = AnalyticsSessionRecord()
            r.sessionId = raw.sessionId
            r.projectName = raw.projectName
            r.startTime = raw.startTime ?? Date()
            r.durationMinutes = raw.durationMinutes ?? 0
            r.inputTokens = raw.tokenUsage.inputTokens
            r.outputTokens = raw.tokenUsage.outputTokens
            r.cacheCreationTokens = raw.tokenUsage.cacheCreationInputTokens
            r.cacheReadTokens = raw.tokenUsage.cacheReadInputTokens
            r.costUSD = raw.costUSD
            r.messageCount = raw.messageCount
            r.toolCallCount = raw.toolCallCount
            r.modelName = raw.model
            r.summary = raw.summary ?? ""
            r.firstPrompt = raw.firstPrompt ?? ""
            return r
        }

        dailyStats = rawDailyStats.map { raw in
            var r = AnalyticsDailyStats()
            r.date = raw.date
            r.dateString = raw.dateString
            r.sessionCount = raw.sessionCount
            r.messageCount = raw.totalMessages
            r.toolCallCount = raw.totalToolCalls
            r.totalInputTokens = raw.totalTokenUsage.inputTokens
            r.totalOutputTokens = raw.totalTokenUsage.outputTokens
            r.totalCacheCreationTokens = raw.totalTokenUsage.cacheCreationInputTokens
            r.totalCacheReadTokens = raw.totalTokenUsage.cacheReadInputTokens
            r.totalCostUSD = raw.totalCostUSD
            return r
        }

        if let raw = rawLimits {
            var r = AnalyticsUsageLimitsRecord()
            r.fiveHourPercent = raw.fiveHourPct
            r.sevenDayPercent = raw.sevenDayPct
            r.fiveHourResetsAt = raw.fiveHourResetsAt
            r.sevenDayResetsAt = raw.sevenDayResetsAt
            r.lastUpdated = Date()
            usageLimits = r
        }

        lastSyncDate = Date()
        isSyncing = false
        print("[ClaudeAnalyticsStore] Sync complete — \(sessions.count) sessions, \(dailyStats.count) days")
    }

    func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        fileWatcher.onChange = { [weak self] in
            Task { await self?.syncNow() }
        }
        fileWatcher.start()
        Task { await syncNow() }
    }

    func stopWatching() {
        fileWatcher.stop()
        isWatching = false
    }

    // MARK: - Convenience Queries

    var todayStats: AnalyticsDailyStats? {
        let today = AnalyticsDailyStats.makeDateString(from: Date())
        return dailyStats.first { $0.dateString == today }
    }

    var recentSessions: [AnalyticsSessionRecord] {
        Array(sessions.prefix(5))
    }
}
