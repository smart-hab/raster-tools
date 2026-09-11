//
//  CalendarView.swift
//  RasterTools
//
//  Created by Marek on 2026-07-08.
//

import SwiftUI

/// A large, single-month calendar grid rendered like Calendar.app's Month view.
///
/// Year and month are directly changeable via the header controls. The view is
/// generic over its day-cell content: it computes the days of the displayed month
/// (as UTC-midnight `Date`s) and hands each to `dayContent`. It holds no
/// domain knowledge — callers paint whatever they like into each cell.
struct CalendarView<DayContent: View>: View {
    @Binding var year: Int
    @Binding var month: Int          // 1...12
    let dayContent: (Date) -> DayContent

    init(
        year: Binding<Int>,
        month: Binding<Int>,
        @ViewBuilder dayContent: @escaping (Date) -> DayContent
    ) {
        self._year = year
        self._month = month
        self.dayContent = dayContent
    }

    private var calendar: Calendar { Date.utcCalendar }

    private var symbolCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US")
        return c
    }

    private var monthSymbols: [String] { symbolCalendar.monthSymbols }
    private var weekdaySymbols: [String] { symbolCalendar.shortWeekdaySymbols }

    /// First day of the displayed month, UTC midnight.
    private var monthStart: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    /// Number of days in the displayed month.
    private var dayCount: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    /// Leading empty cells before day 1 (0-based weekday offset).
    private var leadingBlanks: Int {
        // weekday is 1...7 with 1 == Sunday; firstWeekday is also 1 here.
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            grid
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Picker("Month", selection: $month) {
                ForEach(1...12, id: \.self) { m in
                    Text(monthSymbols[m - 1]).tag(m)
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("Year", selection: $year) {
                ForEach(yearRange, id: \.self) { y in
                    Text(verbatim: String(y)).tag(y)
                }
            }
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button { step(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .font(.title2.weight(.semibold))
    }

    private var yearRange: [Int] {
        // Generous range centered so the current year is always selectable.
        Array((year - 10)...(year + 10))
    }

    private func step(_ delta: Int) {
        var m = month + delta
        var y = year
        while m < 1 { m += 12; y -= 1 }
        while m > 12 { m -= 12; y += 1 }
        month = m
        year = y
    }

    // MARK: - Weekday row

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(orderedWeekdays.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var orderedWeekdays: [String] {
        let first = calendar.firstWeekday - 1
        return (0..<7).map { weekdaySymbols[($0 + first) % 7] }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            // Negative ids so leading blanks never collide with day-number ids.
            ForEach(-leadingBlanks..<0, id: \.self) { _ in
                Color.clear
                    .frame(minHeight: 84)
            }
            ForEach(1...dayCount, id: \.self) { day in
                let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
                dayContent(date)
                    .frame(maxWidth: .infinity, minHeight: 84)
            }
        }
    }
}
