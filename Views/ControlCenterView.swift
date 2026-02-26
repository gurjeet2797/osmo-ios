import SwiftUI

struct ControlCenterView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .calendar
    @State private var currentMonth = Date()

    enum Tab: String, CaseIterable {
        case calendar = "Calendar"
        case commute = "Commute"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            // Tab selector
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? .white.opacity(0.12) : .clear)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Content
            switch selectedTab {
            case .calendar:
                calendarContent
            case .commute:
                commuteContent
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.fraction(0.8)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground {
            glassBackground
        }
    }

    // MARK: - Glass Background

    private var glassBackground: some View {
        ZStack {
            Color.black.opacity(0.4)
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    .white.opacity(0.06),
                    .clear,
                    .white.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 32))
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Month header
                monthHeader

                // Day-of-week labels
                dayOfWeekLabels

                // Calendar grid
                calendarGrid

                // Upcoming events
                upcomingEvents
            }
            .padding(.horizontal, 20)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Text(monthYearString)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var dayOfWeekLabels: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let days = generateDaysForMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { day in
                if let day {
                    let isToday = Calendar.current.isDateInToday(day)
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.system(size: 14, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .white : .white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(isToday ? .white.opacity(0.15) : .clear)
                        )
                } else {
                    Color.clear
                        .frame(width: 36, height: 36)
                }
            }
        }
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UPCOMING")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 8)

            if viewModel.isLoadingEvents {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if viewModel.upcomingEvents.isEmpty {
                Text("No upcoming events")
                    .font(.system(size: 13, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.upcomingEvents) { event in
                    eventRow(time: event.formattedTime, title: event.title)
                }
            }
        }
        .task {
            viewModel.fetchUpcomingEvents()
        }
    }

    private func eventRow(time: String, title: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.3))
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(time)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
                .stroke(.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Commute Placeholder

    private var commuteContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "car.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.15))
            Text("Coming soon")
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
        }
    }

    // MARK: - Calendar Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    private func generateDaysForMonth() -> [Date?] {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: currentMonth)
        guard let firstDay = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: firstDay) else {
            return []
        }

        let weekday = cal.component(.weekday, from: firstDay)
        // Pad leading empty days (Sunday = 1)
        var days: [Date?] = Array(repeating: nil, count: weekday - 1)

        for day in range {
            var dc = components
            dc.day = day
            days.append(cal.date(from: dc))
        }

        return days
    }
}
