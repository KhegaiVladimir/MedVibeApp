import SwiftUI
import SwiftData

enum HistoryRange: String, CaseIterable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedRange: HistoryRange = .week
    @State private var logsByDate: [Date: [DailyLogEntry]] = [:]
    @State private var completionRate: Double = 0.0
    @State private var summaryCounts: (completed: Int, skipped: Int, missed: Int, paused: Int) = (0, 0, 0, 0)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    // Range selector
                    rangeSelector
                    
                    // Summary card
                    summaryCard
                    
                    // Log entries grouped by date
                    if !logsByDate.isEmpty {
                        logEntriesByDate
                    } else {
                        emptyStateView
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadLogs()
                // Backfill on first appear
                Task { @MainActor in
                    await HistoryService.shared.backfillMissingLogs(lastNDays: 14, modelContext: modelContext)
                    loadLogs()
                }
            }
            .onChange(of: selectedRange) { _, _ in
                loadLogs()
            }
        }
    }
    
    // MARK: - Range Selector
    
    private var rangeSelector: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(HistoryRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Completion rate
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completion Rate")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    Text("\(Int(completionRate * 100))%")
                        .font(DesignSystem.Typography.title2)
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
                
                Spacer()
                
                // Progress circle
                ZStack {
                    Circle()
                        .stroke(DesignSystem.Colors.textTertiary.opacity(0.15), lineWidth: 3.5)
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .trim(from: 0, to: completionRate)
                        .stroke(DesignSystem.Colors.primary, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))
                }
            }
            
            Divider()
            
            // Status counts
            HStack(spacing: DesignSystem.Spacing.md) {
                SummaryBadge(
                    title: "Completed",
                    count: summaryCounts.completed,
                    color: DesignSystem.Colors.success
                )
                
                SummaryBadge(
                    title: "Skipped",
                    count: summaryCounts.skipped,
                    color: DesignSystem.Colors.warning
                )
                
                SummaryBadge(
                    title: "Missed",
                    count: summaryCounts.missed,
                    color: DesignSystem.Colors.error
                )
                
                SummaryBadge(
                    title: "Paused",
                    count: summaryCounts.paused,
                    color: DesignSystem.Colors.textTertiary
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
    
    // MARK: - Log Entries By Date
    
    private var logEntriesByDate: some View {
        let sortedDates = logsByDate.keys.sorted(by: >) // Most recent first
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            ForEach(sortedDates, id: \.self) { date in
                if let entries = logsByDate[date] {
                    DateSection(date: date, entries: entries)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("No History Yet")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text("History is automatically created when you:\n• Complete reminders\n• Skip reminders\n• Miss scheduled reminders\n\nMissed reminders are backfilled when you open the app.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
    }
    
    // MARK: - Helper Methods
    
    private func loadLogs() {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        
        let (startDate, endDate): (Date, Date)
        
        switch selectedRange {
        case .today:
            startDate = todayStart
            endDate = todayStart
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            endDate = todayStart
        case .month:
            startDate = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            endDate = todayStart
        }
        
        // Fetch logs grouped by date
        logsByDate = HistoryService.shared.fetchLogsGroupedByDate(
            startDate: startDate,
            endDate: endDate,
            modelContext: modelContext
        )
        
        // Calculate completion rate
        completionRate = HistoryService.shared.calculateCompletionRate(
            startDate: startDate,
            endDate: endDate,
            modelContext: modelContext
        )
        
        // Calculate summary counts
        let allEntries = Array(logsByDate.values.flatMap { $0 })
        summaryCounts = (
            completed: allEntries.filter { $0.isCompleted }.count,
            skipped: allEntries.filter { $0.isSkipped }.count,
            missed: allEntries.filter { $0.isMissed }.count,
            paused: allEntries.filter { $0.isPaused }.count
        )
    }
}

// MARK: - Date Section

struct DateSection: View {
    let date: Date
    let entries: [DailyLogEntry]
    
    private var dateString: String {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        
        if calendar.isDate(date, inSameDayAs: todayStart) {
            return "Today"
        } else if calendar.isDate(date, inSameDayAs: yesterdayStart) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Date header
            Text(dateString)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.xs)
            
            // Entries for this date
            VStack(spacing: 6) {
                ForEach(entries.sorted(by: { $0.timestamp > $1.timestamp })) { entry in
                    LogEntryCard(entry: entry)
                }
            }
        }
    }
}

// MARK: - Summary Badge

struct SummaryBadge: View {
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(color)
            
            Text(title)
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

// MARK: - Log Entry Card

struct LogEntryCard: View {
    let entry: DailyLogEntry
    @Environment(\.modelContext) private var modelContext
    
    private var statusColor: Color {
        switch entry.status {
        case "completed": return DesignSystem.Colors.success
        case "skipped": return DesignSystem.Colors.warning
        case "missed": return DesignSystem.Colors.error
        case "paused": return DesignSystem.Colors.textTertiary
        default: return DesignSystem.Colors.textSecondary
        }
    }
    
    private var statusLabel: String {
        switch entry.status {
        case "completed": return "Completed"
        case "skipped": return "Skipped"
        case "missed": return "Missed"
        case "paused": return "Paused"
        default: return entry.status.capitalized
        }
    }
    
    private var timeDisplay: String {
        if entry.isMissed {
            return "Missed"
        } else {
            // Use timeSnapshot from entry (no model access needed)
            return entry.timeSnapshot ?? "--:--"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // Time/Status
            VStack(spacing: 2) {
                Text(timeDisplay)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(statusColor)
                    .frame(width: 60, alignment: .leading)
                
                if entry.wasRepeatingSnapshot {
                    Image(systemName: "repeat")
                        .font(.system(size: 8))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(entry.titleSnapshot.isEmpty ? "Unknown" : entry.titleSnapshot)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                HStack(spacing: DesignSystem.Spacing.xs) {
                    // Status badge
                    Text(statusLabel)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(4)
                    
                    // Type badge - use snapshot field
                    if entry.wasRepeatingSnapshot {
                        Text("Weekly")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.textTertiary.opacity(0.1))
                            .cornerRadius(4)
                    } else {
                        Text("One-time")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.textTertiary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }
}
