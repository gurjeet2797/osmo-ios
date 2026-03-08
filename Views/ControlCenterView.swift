import SwiftUI

struct ControlCenterView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .calendar
    @State private var currentMonth = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    enum Tab: String, CaseIterable {
        case calendar = "Calendar"
        case commute = "Commute"
        case settings = "Settings"
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
                        HapticEngine.tick()
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
            case .settings:
                settingsContent
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
                    updateSelectedDateForMonth()
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
                    updateSelectedDateForMonth()
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
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
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
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                    Button {
                        HapticEngine.tick()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = Calendar.current.startOfDay(for: day)
                        }
                    } label: {
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.system(size: 14, weight: (isToday || isSelected) ? .bold : .regular))
                            .foregroundStyle((isToday || isSelected) ? .white : .white.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(isSelected ? .white.opacity(0.25) : .clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: (isToday && !isSelected) ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 36, height: 36)
                }
            }
        }
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selected day header
            Text(selectedDayHeaderString)
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
            } else {
                let dayEvents = selectedDayEvents
                if dayEvents.isEmpty {
                    Text("No events")
                        .font(.system(size: 13, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    ForEach(dayEvents) { event in
                        eventRow(time: event.formattedTime, title: event.title)
                    }
                }

                // Coming up — next 2 days
                let upcoming = nextTwoDaysSummary
                if !upcoming.isEmpty {
                    Text("COMING UP")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 12)

                    ForEach(upcoming, id: \.date) { entry in
                        Text(dayHeaderString(for: entry.date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 4)

                        if entry.events.isEmpty {
                            Text("No events")
                                .font(.system(size: 12, weight: .light, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.2))
                                .padding(.leading, 4)
                        } else {
                            ForEach(entry.events) { event in
                                eventRow(time: event.formattedTime, title: event.title)
                            }
                        }
                    }
                }
            }
        }
        .task {
            viewModel.fetchUpcomingEvents(days: 7)
        }
        .onChange(of: selectedDate) {
            let cal = Calendar.current
            let daysOut = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: selectedDate).day ?? 0
            if daysOut > 5 {
                viewModel.fetchUpcomingEvents(days: min(daysOut + 3, 14), forceRefresh: true)
            }
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
            if let commute = viewModel.commuteWidgetData,
               commute.destination != nil {
                Spacer()
                if let duration = commute.duration {
                    Text(duration)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                if let destination = commute.destination {
                    Text(destination)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let distance = commute.distance {
                    Text(distance)
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                if commute.duration == nil {
                    Text("Destination saved")
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
            } else {
                Spacer()
                Image(systemName: "car.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.15))
                Text("Say \"my work address is...\" to enable commute estimates")
                    .font(.system(size: 12, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Spacer()
            }
        }
        .task {
            viewModel.fetchWidgetData(forceRefresh: true)
        }
    }

    // MARK: - Settings Content

    private var settingsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Home Widgets section
                settingsSection("HOME WIDGETS") {
                    ForEach(HomeWidgetType.allCases, id: \.self) { widget in
                        widgetToggleRow(widget)
                    }
                }

                // Account section
                settingsSection("ACCOUNT") {
                    if let email = viewModel.authManager?.userEmail {
                        settingsRow(icon: "envelope", label: email)
                    }
                    // Subscription
                    HStack {
                        Image(systemName: "crown")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 24)
                        Text("Subscription")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        if viewModel.subscriptionTier == "dev" {
                            Text("Developer")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.purple.opacity(0.15)))
                        } else if viewModel.subscriptionTier == "pro" {
                            Text("Pro")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.green.opacity(0.15)))
                        } else {
                            Button {
                                viewModel.showPaywall = true
                            } label: {
                                Text("Upgrade")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.1)))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(settingsRowBackground)
                }

                // About section
                settingsSection("ABOUT") {
                    settingsRow(icon: "info.circle", label: "Version 1.0.0")
                    if viewModel.isDevMode {
                        settingsRow(icon: "hammer", label: "Developer Mode")
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Settings Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.3))
            content()
        }
    }

    private func settingsRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(settingsRowBackground)
    }

    private var settingsRowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.white.opacity(0.05))
            .stroke(.white.opacity(0.06), lineWidth: 0.5)
    }

    private var widgetIcons: [HomeWidgetType: String] {
        [.calendar: "calendar", .email: "envelope", .commute: "car", .briefing: "sparkles", .weather: "cloud.sun"]
    }

    private var widgetLabels: [HomeWidgetType: String] {
        [.calendar: "Calendar", .email: "Email", .commute: "Commute", .briefing: "Briefing", .weather: "Weather"]
    }

    private func widgetToggleRow(_ widget: HomeWidgetType) -> some View {
        let isOn = viewModel.homeWidgets.contains(widget)
        return HStack(spacing: 12) {
            Image(systemName: widgetIcons[widget] ?? "square")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24)
            Text(widgetLabels[widget] ?? widget.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    HapticEngine.tick()
                    if newValue {
                        viewModel.homeWidgets.append(widget)
                    } else {
                        viewModel.homeWidgets.removeAll { $0 == widget }
                    }
                    viewModel.saveWidgetPreferences()
                }
            ))
            .tint(.white.opacity(0.4))
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(settingsRowBackground)
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

    // MARK: - Date Selection Helpers

    private func updateSelectedDateForMonth() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // If today is in the new month, select today; otherwise select the 1st
        let monthComponents = cal.dateComponents([.year, .month], from: currentMonth)
        let todayComponents = cal.dateComponents([.year, .month], from: today)
        if monthComponents.year == todayComponents.year && monthComponents.month == todayComponents.month {
            selectedDate = today
        } else if let firstOfMonth = cal.date(from: monthComponents) {
            selectedDate = firstOfMonth
        }
    }

    private func events(for date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        return viewModel.upcomingEvents.filter { event in
            guard let eventDate = event.startDate else { return false }
            return cal.isDate(eventDate, inSameDayAs: date)
        }
    }

    private var selectedDayEvents: [CalendarEvent] {
        events(for: selectedDate)
    }

    private var nextTwoDaysSummary: [(date: Date, events: [CalendarEvent])] {
        let cal = Calendar.current
        return (1...2).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: selectedDate) else { return nil }
            return (date: date, events: events(for: date))
        }
    }

    private var selectedDayHeaderString: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "TODAY"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate).uppercased()
    }

    private func dayHeaderString(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today"
        }
        if cal.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}
