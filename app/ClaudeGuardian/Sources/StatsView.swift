// StatsView.swift
// Analytics UI for ClaudeGuardian — styled to match ClaudeWatch

import SwiftUI
import Charts

// MARK: - Color Palette (matches ClaudeWatch dark purple theme)

private let bgColor    = Color(red: 0.11, green: 0.11, blue: 0.16)
private let cardColor  = Color(red: 0.16, green: 0.16, blue: 0.22)
private let card2Color = Color(red: 0.13, green: 0.13, blue: 0.19)

// MARK: - StatsMenuView

struct StatsMenuView: View {

    @ObservedObject var store: ClaudeAnalyticsStore
    @State private var selectedTab = 0

    private var allDailyStats: [AnalyticsDailyStats] {
        store.dailyStats.sorted { $0.dateString > $1.dateString }
    }
    private var allSessions: [AnalyticsSessionRecord] {
        store.sessions.sorted { $0.startTime > $1.startTime }
    }
    private var todayStats: AnalyticsDailyStats? { store.todayStats }
    private var recentSessions: [AnalyticsSessionRecord] { store.recentSessions }
    private var currentLimits: AnalyticsUsageLimitsRecord? { store.usageLimits }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            ScrollView {
                VStack(spacing: 12) {
                    switch selectedTab {
                    case 0: todayTab
                    case 1: allTimeTab
                    case 2: projectsTab
                    case 3: trendsTab
                    default: todayTab
                    }
                }
                .padding(12)
            }
            footer
        }
        .frame(width: 400, height: 480)
        .background(bgColor)
        .task { await store.syncNow() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.purple)
            Text("Claude Analytics")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                Task { await store.syncNow() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(store.isSyncing ? .degrees(360) : .zero)
                        .animation(store.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                   value: store.isSyncing)
                    Text(store.isSyncing ? "Syncing…" : "Sync")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(store.isSyncing ? Color.gray.opacity(0.5) : Color.purple.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.isSyncing)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabBtn(title: "Today",    icon: "calendar",                  tab: 0)
            tabBtn(title: "All Time", icon: "infinity",                   tab: 1)
            tabBtn(title: "Projects", icon: "folder.fill",                tab: 2)
            tabBtn(title: "Trends",   icon: "chart.line.uptrend.xyaxis", tab: 3)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func tabBtn(title: String, icon: String, tab: Int) -> some View {
        let active = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13, weight: active ? .semibold : .regular))
                Text(title).font(.system(size: 9, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? .purple : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(active ? Color.purple.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today Tab

    private var todayTab: some View {
        VStack(spacing: 10) {
            todayStatsCard
            tokenBreakdownCard
            rateLimitsCard
            recentSessionsCard
        }
    }

    private var todayStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                statCell(icon: "dollarsign.circle.fill", color: .green,
                         value: todayStats.map { String(format: "$%.2f", $0.totalCostUSD) } ?? "$0.00",
                         label: "Cost")
                thinDivider()
                statCell(icon: "terminal.fill", color: .blue,
                         value: "\(todayStats?.sessionCount ?? 0)",
                         label: "Sessions")
                thinDivider()
                statCell(icon: "bubble.left.and.bubble.right.fill", color: .orange,
                         value: "\(todayStats?.messageCount ?? 0)",
                         label: "Messages")
                thinDivider()
                statCell(icon: "character.textbox", color: .purple,
                         value: abbreviate((todayStats?.totalInputTokens ?? 0) + (todayStats?.totalOutputTokens ?? 0)),
                         label: "Tokens")
            }
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
    }

    private var tokenBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Token Breakdown").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            let input      = todayStats?.totalInputTokens ?? 0
            let output     = todayStats?.totalOutputTokens ?? 0
            let cacheWrite = todayStats?.totalCacheCreationTokens ?? 0
            let cacheRead  = todayStats?.totalCacheReadTokens ?? 0
            let total      = max(input + output + cacheWrite + cacheRead, 1)

            tokenBar(label: "Input",       value: input,      total: total, color: Color(red: 0.26, green: 0.53, blue: 0.96))
            tokenBar(label: "Output",      value: output,     total: total, color: Color(red: 0.18, green: 0.7,  blue: 0.40))
            tokenBar(label: "Cache Write", value: cacheWrite, total: total, color: Color(red: 0.78, green: 0.28, blue: 0.90))
            tokenBar(label: "Cache Read",  value: cacheRead,  total: total, color: Color(red: 0.10, green: 0.80, blue: 0.85))
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
    }

    private var rateLimitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Rate Limits").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            if let l = currentLimits {
                rateLimitRow(label: "5-Hour Window", pct: l.fiveHourPercent)
                rateLimitRow(label: "7-Day Window",  pct: l.sevenDayPercent)
            } else {
                Text("No rate limit data yet")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Recent Sessions").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            if recentSessions.isEmpty {
                Text("No sessions yet").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6)
            } else {
                ForEach(Array(recentSessions.enumerated()), id: \.offset) { idx, session in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue).font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.projectName.isEmpty ? "Unnamed" : session.projectName)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            Text(timeAgo(session.startTime))
                                .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4))
                        }
                        Spacer()
                        Text(String(format: "$%.3f", session.costUSD))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green).monospacedDigit()
                    }
                    .padding(.vertical, 3)
                    if idx < recentSessions.count - 1 {
                        Divider().background(Color.white.opacity(0.08))
                    }
                }
            }
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - All Time Tab

    private var allTimeCost: Double    { allDailyStats.reduce(0) { $0 + $1.totalCostUSD } }
    private var allTimeSessions: Int   { allDailyStats.reduce(0) { $0 + $1.sessionCount } }
    private var allTimeMessages: Int   { allDailyStats.reduce(0) { $0 + $1.messageCount } }
    private var allTimeInput: Int      { allDailyStats.reduce(0) { $0 + $1.totalInputTokens } }
    private var allTimeOutput: Int     { allDailyStats.reduce(0) { $0 + $1.totalOutputTokens } }
    private var allTimeCacheWrite: Int { allDailyStats.reduce(0) { $0 + $1.totalCacheCreationTokens } }
    private var allTimeCacheRead: Int  { allDailyStats.reduce(0) { $0 + $1.totalCacheReadTokens } }
    private var allTimeActiveDays: Int { allDailyStats.count }

    private var allTimeTab: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "infinity").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("All Time").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    statCell(icon: "dollarsign.circle.fill", color: .green,
                             value: String(format: "$%.2f", allTimeCost), label: "Total Cost")
                    thinDivider()
                    statCell(icon: "terminal.fill", color: .blue,
                             value: "\(allTimeSessions)", label: "Sessions")
                    thinDivider()
                    statCell(icon: "bubble.left.and.bubble.right.fill", color: .orange,
                             value: "\(allTimeMessages)", label: "Messages")
                }
                HStack(spacing: 0) {
                    statCell(icon: "character.textbox", color: .purple,
                             value: abbreviate(allTimeInput + allTimeOutput), label: "Tokens")
                    thinDivider()
                    statCell(icon: "calendar.badge.checkmark", color: .teal,
                             value: "\(allTimeActiveDays)", label: "Active Days")
                    thinDivider()
                    statCell(icon: "chart.bar.fill", color: .pink,
                             value: allTimeActiveDays > 0
                                ? String(format: "$%.2f", allTimeCost / Double(allTimeActiveDays)) : "$0",
                             label: "Avg/Day")
                }
            }
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Token Breakdown (All Time)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                let total = max(allTimeInput + allTimeOutput + allTimeCacheWrite + allTimeCacheRead, 1)
                tokenBar(label: "Input",       value: allTimeInput,      total: total, color: Color(red: 0.26, green: 0.53, blue: 0.96))
                tokenBar(label: "Output",      value: allTimeOutput,     total: total, color: Color(red: 0.18, green: 0.7,  blue: 0.40))
                tokenBar(label: "Cache Write", value: allTimeCacheWrite, total: total, color: Color(red: 0.78, green: 0.28, blue: 0.90))
                tokenBar(label: "Cache Read",  value: allTimeCacheRead,  total: total, color: Color(red: 0.10, green: 0.80, blue: 0.85))
            }
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "cpu").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Models Used").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                let modelGroups = Dictionary(grouping: allSessions) { s -> String in
                    let m = s.modelName.lowercased()
                    if m.contains("opus")   { return "Opus" }
                    if m.contains("haiku")  { return "Haiku" }
                    if m.contains("sonnet") { return "Sonnet" }
                    return s.modelName.isEmpty ? "Unknown" : s.modelName
                }
                ForEach(Array(modelGroups.sorted { $0.value.count > $1.value.count }.prefix(5)), id: \.key) { model, sess in
                    HStack {
                        Circle().fill(modelColor(model)).frame(width: 8, height: 8)
                        Text(model).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        Spacer()
                        Text("\(sess.count) sessions").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45))
                        Text(String(format: "$%.2f", sess.reduce(0) { $0 + $1.costUSD }))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green).monospacedDigit()
                    }
                }
            }
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Projects Tab

    private var projectsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Cost by Project").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            let projectGroups = Dictionary(grouping: allSessions) { $0.projectName }
            let sorted = projectGroups
                .map { (name: $0.key, sessArr: $0.value, cost: $0.value.reduce(0) { $0 + $1.costUSD }) }
                .sorted { $0.cost > $1.cost }
            let maxCost = sorted.first?.cost ?? 1

            if sorted.isEmpty {
                Text("No project data yet").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
            } else {
                ForEach(Array(sorted.prefix(10).enumerated()), id: \.offset) { idx, project in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(project.name.isEmpty ? "Unnamed" : project.name)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(String(format: "$%.2f", project.cost))
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green).monospacedDigit()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.12)).frame(height: 8)
                                RoundedRectangle(cornerRadius: 4).fill(
                                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing)
                                ).frame(width: max(geo.size.width * (project.cost / maxCost), 6), height: 8)
                            }
                        }
                        .frame(height: 8)
                        HStack(spacing: 10) {
                            Text("\(project.sessArr.count) sessions")
                            Text("\(project.sessArr.reduce(0) { $0 + $1.messageCount }) msgs")
                            Text(abbreviate(project.sessArr.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }) + " tokens")
                        }
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.35))
                    }
                    .padding(.vertical, 4)
                    if idx < min(sorted.count, 10) - 1 {
                        Divider().background(Color.white.opacity(0.08))
                    }
                }
            }
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Trends Tab

    private struct DayPoint: Identifiable {
        let id = UUID(); let date: Date; let cost: Double
    }

    private var last7Days: [DayPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        let cutoffStr = AnalyticsDailyStats.makeDateString(from: cutoff)
        return allDailyStats
            .filter { $0.dateString >= cutoffStr }
            .sorted { $0.dateString < $1.dateString }
            .compactMap { stat -> DayPoint? in
                guard let date = statsDateFormatter.date(from: stat.dateString) else { return nil }
                return DayPoint(date: date, cost: stat.totalCostUSD)
            }
    }

    private var trendsTab: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Daily Cost (Last 7 Days)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                let points = last7Days
                if points.isEmpty {
                    Text("Not enough data yet").font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
                } else {
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date, unit: .day), y: .value("Cost", point.cost))
                            .foregroundStyle(Color.purple).interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Date", point.date, unit: .day), y: .value("Cost", point.cost))
                            .foregroundStyle(LinearGradient(colors: [Color.purple.opacity(0.35), .clear],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date, unit: .day), y: .value("Cost", point.cost))
                            .foregroundStyle(.purple).symbolSize(28)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                                .font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.5))
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(String(format: "$%.0f", d)).font(.system(size: 9))
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }
                            }
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        }
                    }
                    .chartBackground { _ in card2Color }
                    .frame(height: 140)

                    let weekTotal = points.reduce(0) { $0 + $1.cost }
                    let weekAvg   = points.isEmpty ? 0 : weekTotal / Double(points.count)
                    let weekMax   = points.map(\.cost).max() ?? 0
                    HStack(spacing: 0) {
                        miniStat(label: "Total",   value: String(format: "$%.2f", weekTotal), color: .green)
                        thinDivider()
                        miniStat(label: "Average", value: String(format: "$%.2f", weekAvg),   color: .blue)
                        thinDivider()
                        miniStat(label: "Peak",    value: String(format: "$%.2f", weekMax),   color: .red)
                    }
                }
            }
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Daily History (Last 30 Days)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                let days = Array(allDailyStats.sorted { $0.dateString > $1.dateString }.prefix(30))
                if days.isEmpty {
                    Text("No data yet").font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6)
                } else {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                        HStack {
                            Text(formatDateLabel(day.dateString))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 72, alignment: .leading)
                            Text("\(day.sessionCount)s")
                                .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4)).frame(width: 24)
                            Text("\(day.messageCount)m")
                                .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4)).frame(width: 30)
                            Spacer()
                            Text(abbreviate(day.totalInputTokens + day.totalOutputTokens))
                                .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4)).monospacedDigit()
                            Text(String(format: "$%.2f", day.totalCostUSD))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                                .monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                        if idx < days.count - 1 { Divider().background(Color.white.opacity(0.07)) }
                    }
                }
            }
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text("Auto-sync on").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4))
            Text("·").foregroundStyle(Color.white.opacity(0.3))
            Text(store.lastSyncDate.map { "Synced \(timeAgo($0))" } ?? "Syncing…")
                .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(card2Color)
    }

    // MARK: - Shared Components

    private func statCell(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 18, weight: .semibold))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func miniStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func tokenBar(label: String, value: Int, total: Int, color: Color) -> some View {
        let fraction = Double(value) / Double(total)
        let trackColor = color.opacity(0.15)
        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 74, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(trackColor).frame(height: 7)
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: max(geo.size.width * fraction, 3), height: 7)
                }
            }
            .frame(height: 7)
            Text(abbreviate(value))
                .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
                .monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    private func rateLimitRow(label: String, pct: Double) -> some View {
        let fraction = min(pct / 100.0, 1.0)
        let color: Color = fraction < 0.6 ? .green : fraction < 0.85 ? .orange : .red
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.1f%%", pct))
                    .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(color)
                        .frame(width: max(geo.size.width * fraction, 4), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private func thinDivider() -> some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 44)
    }

    // MARK: - Helpers

    private func modelColor(_ model: String) -> Color {
        switch model {
        case "Opus":   return .purple
        case "Sonnet": return .orange
        case "Haiku":  return .teal
        default:       return .gray
        }
    }

    private var statsDateFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }

    private func abbreviate(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:     return String(format: "%.0fK", Double(value) / 1_000)
        default:           return "\(value)"
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        switch s {
        case ..<60:    return "just now"
        case ..<3600:  return "\(Int(s / 60))m ago"
        case ..<86400: return "\(Int(s / 3600))h ago"
        default:       return "\(Int(s / 86400))d ago"
        }
    }

    private func formatDateLabel(_ dateString: String) -> String {
        guard let date = statsDateFormatter.date(from: dateString) else { return dateString }
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"; return fmt.string(from: date)
    }
}
