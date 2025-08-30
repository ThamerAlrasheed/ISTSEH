import SwiftUI

// MARK: - Public API
/// A reusable Apple-Calendar-style date picker that supports Weekly/Monthly layouts.
/// - Parameters:
///   - selection: Binding to the currently selected Date.
///   - mode: Initial mode (.weekly or .monthly); user can toggle using segmented control.
///   - calendar: Calendar used for calculations (defaults to .current).
///   - allowsSelectingOutsideCurrentMonth: If true, monthly view allows selecting
///     days in the leading/trailing month shown in the grid. Defaults to true.
public struct CalendarView: View {
    @Binding private var selection: Date
    @State private var mode: CalendarMode
    private let calendar: Calendar
    private let allowsSelectingOutsideCurrentMonth: Bool

    public init(
        selection: Binding<Date>,
        initialMode: CalendarMode = .monthly,
        calendar: Calendar = .current,
        allowsSelectingOutsideCurrentMonth: Bool = true
    ) {
        self._selection = selection
        self._mode = State(initialValue: initialMode)
        self.calendar = calendar
        self.allowsSelectingOutsideCurrentMonth = allowsSelectingOutsideCurrentMonth
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Mode switch
            Picker("", selection: $mode) {
                Text("Weekly").tag(CalendarMode.weekly)
                Text("Monthly").tag(CalendarMode.monthly)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if mode == .weekly {
                WeeklyCalendar(
                    selection: $selection,
                    calendar: calendar
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                MonthlyCalendar(
                    selection: $selection,
                    calendar: calendar,
                    allowsSelectingOutsideCurrentMonth: allowsSelectingOutsideCurrentMonth
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }
}

// MARK: - Modes
public enum CalendarMode: Hashable {
    case weekly
    case monthly
}

// MARK: - Weekly
private struct WeeklyCalendar: View {
    @Binding var selection: Date
    let calendar: Calendar

    @State private var referenceWeekStart: Date

    init(selection: Binding<Date>, calendar: Calendar) {
        self._selection = selection
        self.calendar = calendar
        // Align our reference to the start of the selected date's week
        let start = calendar.startOfWeek(for: selection.wrappedValue)
        self._referenceWeekStart = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 8) {
            Header(
                title: weekTitle,
                onPrev: { moveWeek(by: -1) },
                onNext: { moveWeek(by: 1) }
            )

            WeekdayRow(calendar: calendar)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: referenceWeekStart)!
                    DayCell(
                        date: day,
                        calendar: calendar,
                        isSelected: calendar.isDate(day, inSameDayAs: selection),
                        isToday: calendar.isDateInToday(day),
                        isDimmed: false
                    ) {
                        selection = day
                        // When user picks a new date outside this week (rare via external binding),
                        // keep week aligned to that date.
                        referenceWeekStart = calendar.startOfWeek(for: day)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .onChange(of: selection) { newValue in
            // If binding is changed externally, keep calendar in view
            let start = calendar.startOfWeek(for: newValue)
            if !calendar.isDate(start, inSameDayAs: referenceWeekStart) {
                referenceWeekStart = start
            }
        }
    }

    private var weekTitle: String {
        let end = calendar.date(byAdding: .day, value: 6, to: referenceWeekStart)!
        let df = DateFormatter()
        df.calendar = calendar
        df.locale = calendar.locale
        df.dateFormat = titleFormat(for: referenceWeekStart, end: end)
        return df.string(from: referenceWeekStart) + " – " + df.string(from: end)
    }

    private func titleFormat(for start: Date, end: Date) -> String {
        // If months/years differ, include more context
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let sameYear  = calendar.component(.year, from: start)  == calendar.component(.year, from: end)
        if sameYear && sameMonth { return "MMM d" }
        if sameYear { return "MMM d" }
        return "MMM d, yyyy"
    }

    private func moveWeek(by count: Int) {
        if let newStart = calendar.date(byAdding: .weekOfYear, value: count, to: referenceWeekStart) {
            referenceWeekStart = newStart
        }
    }
}

// MARK: - Monthly
private struct MonthlyCalendar: View {
    @Binding var selection: Date
    let calendar: Calendar
    let allowsSelectingOutsideCurrentMonth: Bool

    @State private var visibleMonthAnchor: Date

    init(selection: Binding<Date>, calendar: Calendar, allowsSelectingOutsideCurrentMonth: Bool) {
        self._selection = selection
        self.calendar = calendar
        self.allowsSelectingOutsideCurrentMonth = allowsSelectingOutsideCurrentMonth
        // Anchor shows the first day of the selected date's month
        let anchor = calendar.firstOfMonth(for: selection.wrappedValue)
        self._visibleMonthAnchor = State(initialValue: anchor)
    }

    var body: some View {
        VStack(spacing: 8) {
            Header(
                title: monthTitle,
                onPrev: { shiftMonth(-1) },
                onNext: { shiftMonth(1) }
            )

            WeekdayRow(calendar: calendar)

            // 6 rows x 7 columns to emulate Apple Calendar grid
            let days = calendar.monthGridDates(for: visibleMonthAnchor)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let isCurrentMonth = calendar.isDate(day, equalTo: visibleMonthAnchor, toGranularity: .month)
                    let isDim = !isCurrentMonth
                    DayCell(
                        date: day,
                        calendar: calendar,
                        isSelected: calendar.isDate(day, inSameDayAs: selection),
                        isToday: calendar.isDateInToday(day),
                        isDimmed: isDim
                    ) {
                        if isCurrentMonth || allowsSelectingOutsideCurrentMonth {
                            selection = day
                            if !isCurrentMonth {
                                // If selecting a dimmed day, jump to that month (matches Apple behavior)
                                visibleMonthAnchor = calendar.firstOfMonth(for: day)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .onChange(of: selection) { newValue in
            // Keep month in view if external selection jumps elsewhere
            let monthStart = calendar.firstOfMonth(for: newValue)
            if !calendar.isDate(monthStart, inSameDayAs: visibleMonthAnchor) {
                visibleMonthAnchor = monthStart
            }
        }
    }

    private var monthTitle: String {
        let df = DateFormatter()
        df.calendar = calendar
        df.locale = calendar.locale
        df.dateFormat = "MMMM yyyy"
        return df.string(from: visibleMonthAnchor)
    }

    private func shiftMonth(_ delta: Int) {
        if let newAnchor = calendar.date(byAdding: .month, value: delta, to: visibleMonthAnchor) {
            visibleMonthAnchor = newAnchor
        }
    }
}

// MARK: - Common Header
private struct Header: View {
    let title: String
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .padding(8)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}

// MARK: - Weekday Row
private struct WeekdayRow: View {
    let calendar: Calendar

    var body: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbolsShiftedToFirstWeekday
        HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { s in
                Text(s.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Day Cell
private struct DayCell: View {
    let date: Date
    let calendar: Calendar
    let isSelected: Bool
    let isToday: Bool
    let isDimmed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    // Selected background
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .shadow(color: Color.accentColor.opacity(0.25), radius: 4, x: 0, y: 2)
                    } else if isToday {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 32, height: 32)
                    }

                    Text(dayNumberString)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : (isDimmed ? Color.secondary : Color.primary))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayNumberString: String {
        let d = calendar.component(.day, from: date)
        return String(d)
    }

    private var accessibilityLabel: String {
        let df = DateFormatter()
        df.calendar = calendar
        df.dateStyle = .full
        var base = df.string(from: date)
        if isSelected { base += ", selected" }
        if isToday { base += ", today" }
        return base
    }
}

// MARK: - Calendar helpers
private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    func firstOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }

    /// Dates to render a 6-row monthly grid (42 cells).
    func monthGridDates(for anchor: Date) -> [Date] {
        let firstDay = firstOfMonth(for: anchor)
        let weekday = component(.weekday, from: firstDay)
        // number of leading cells to align to firstWeekday
        let shift = ((weekday - firstWeekday) + 7) % 7
        let start = date(byAdding: .day, value: -shift, to: firstDay) ?? firstDay
        return (0..<42).compactMap { dayOffset in
            date(byAdding: .day, value: dayOffset, to: start)
        }
    }

    var shortStandaloneWeekdaySymbolsShiftedToFirstWeekday: [String] {
        let syms = shortStandaloneWeekdaySymbols
        guard syms.count == 7 else { return syms }
        let idx = (firstWeekday - 1) % 7
        return Array(syms[idx...] + syms[..<idx])
    }
}
