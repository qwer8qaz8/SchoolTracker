import AppKit
import SwiftUI
import SchoolTrackerCore

// MARK: - Subscribe to Family Portal Calendars Sheet

struct CalendarSubscriptionSheet: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel
    @Environment(\.dismiss) private var dismiss

    private let placeholderFeedURL = "webcal://example.client.factsmgt.com/calendar/feed.ics?District=TEST-XX&SessionID=00000000-0000-0000-0000-000000000000"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection

            VStack(alignment: .leading, spacing: 12) {
                ForEach(FamilyPortalCalendarCategory.allCases) { category in
                    CalendarSubscriptionOptionRow(
                        category: category,
                        isSelected: viewModel.isDraftCategorySelected(category),
                        existingSubscription: viewModel.state.subscription(for: category),
                        feedURLBinding: viewModel.draftFeedBinding(for: category),
                        placeholderURL: placeholderFeedURL,
                        onToggle: { isChecked in
                            viewModel.setDraftCategory(category, isSelected: isChecked)
                        },
                        onClearSavedFeed: {
                            viewModel.clearSavedCalendarFeed(for: category)
                        }
                    )
                }
            }

            validationNotice

            Divider()

            footerButtons
        }
        .padding(24)
        .frame(width: 600)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Subscribe to Family Portal Calendars")
                    .font(.title3.weight(.bold))
                Text("Choose which Family Portal calendars you would like to subscribe to:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var validationNotice: some View {
        if let error = viewModel.calendarSubscriptionValidationError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(10)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 8) {
                Image(systemName: viewModel.draftSelectedCalendars.isEmpty ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(viewModel.draftSelectedCalendars.isEmpty ? .orange : .green)
                Text("Choose at least 1 option above. Each selected calendar gets its own space in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(viewModel.draftSelectedCalendars.isEmpty ? .orange : .secondary)
            }
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(viewModel.isSyncingCalendars)

            Spacer()

            Button("Save Subscriptions") {
                Task {
                    if await viewModel.saveCalendarSubscriptions(syncFeedsAfterSave: false) {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSyncingCalendars)

            Button {
                Task {
                    if await viewModel.saveCalendarSubscriptions(syncFeedsAfterSave: true) {
                        dismiss()
                    }
                }
            } label: {
                Label(
                    viewModel.isSyncingCalendars ? "Saving & Syncing…" : "Save & Sync Calendars",
                    systemImage: "checkmark.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSyncingCalendars)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct CalendarSubscriptionOptionRow: View {
    let category: FamilyPortalCalendarCategory
    let isSelected: Bool
    let existingSubscription: FamilyPortalCalendarSubscription
    let feedURLBinding: Binding<String>
    let placeholderURL: String
    let onToggle: (Bool) -> Void
    let onClearSavedFeed: () -> Void

    var body: some View {
        let tint = SchoolTrackerViewModel.calendarCategoryTint(for: category)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Toggle(
                    isOn: Binding(
                        get: { isSelected },
                        set: { onToggle($0) }
                    )
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: category.systemImage)
                            .font(.title3)
                            .foregroundStyle(tint)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                                .font(.headline)
                            Text(category.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)

                Spacer()

                if isSelected {
                    Text("Own Space Enabled")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                }
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 6) {
                    if let redacted = existingSubscription.redactedFeedURL {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved .ics feed: \(redacted)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Clear Feed", role: .destructive, action: onClearSavedFeed)
                                .buttonStyle(.borderless)
                                .font(.caption2)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(
                            existingSubscription.redactedFeedURL != nil
                                ? "Optional: paste a new https:// or webcal:// .ics feed URL to replace…"
                                : "Optional: paste \(category.displayName) https:// or webcal:// .ics feed URL…",
                            text: feedURLBinding
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                        Button {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                feedURLBinding.wrappedValue = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Paste calendar feed URL from clipboard")
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(14)
        .background(isSelected ? tint.opacity(0.06) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? tint.opacity(0.35) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Dedicated Category Space View (School, My Classrooms, My Homework)

struct CalendarCategorySpaceView: View {
    let category: FamilyPortalCalendarCategory
    @ObservedObject var viewModel: SchoolTrackerViewModel

    private var subscription: FamilyPortalCalendarSubscription {
        viewModel.state.subscription(for: category)
    }

    private var allCategoryEvents: [CalendarEvent] {
        viewModel.state.events(for: category)
    }

    private var filteredEvents: [CalendarEvent] {
        viewModel.filteredEvents(for: category)
    }

    private var tint: Color {
        SchoolTrackerViewModel.calendarCategoryTint(for: category)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                spaceHeaderCard

                if !subscription.isSubscribed {
                    unsubscribedSpaceState
                } else {
                    filterToolbar

                    if viewModel.calendarDisplayMode == .split {
                        HStack(alignment: .top, spacing: 20) {
                            CalendarMonthGridView(
                                category: category,
                                events: allCategoryEvents,
                                tint: tint,
                                viewModel: viewModel
                            )
                            .frame(width: 310)

                            agendaSection
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        agendaSection
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(category.displayName)
    }

    private var spaceHeaderCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: category.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(category.displayName)
                        .font(.title2.weight(.bold))
                    Text("Dedicated Space")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                }

                Text(category.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label("\(allCategoryEvents.count) total events", systemImage: "calendar")
                    if let syncedAt = subscription.lastSyncedAt {
                        Label("Feed synced \(syncedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    } else if let redacted = subscription.redactedFeedURL {
                        Label(redacted, systemImage: "link")
                    } else {
                        Label("Synced with local courses & tasks", systemImage: "sparkles")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                if subscription.redactedFeedURL != nil {
                    Button {
                        Task {
                            await viewModel.syncCalendarFeeds(for: category)
                        }
                    } label: {
                        Label(
                            viewModel.isSyncingCalendars ? "Syncing…" : "Sync Feed",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSyncingCalendars)
                }

                Button {
                    viewModel.openNewCalendarEventSheet(for: category)
                } label: {
                    Label("Add Event", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)

                Button("Subscriptions…") {
                    viewModel.openCalendarSubscriptionSheet()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        )
    }

    private var unsubscribedSpaceState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Not Subscribed to \(category.displayName)")
                .font(.headline)
            Text("Enable \(category.displayName) in 'Subscribe to Family Portal Calendars' to activate this space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Subscribe to Family Portal Calendars…") {
                viewModel.openCalendarSubscriptionSheet()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $viewModel.calendarDisplayMode) {
                ForEach(CalendarDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Picker("When", selection: $viewModel.calendarTimeFilter) {
                ForEach(CalendarTimeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .disabled(viewModel.calendarSelectedDay != nil)

            if let selectedDay = viewModel.calendarSelectedDay {
                HStack(spacing: 6) {
                    Text(selectedDay.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))
                    Button {
                        viewModel.calendarSelectedDay = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)
            }

            Spacer()

            TextField("Search \(category.displayName)…", text: $viewModel.calendarSearchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
        }
    }

    @ViewBuilder
    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(category.displayName) Schedule (\(filteredEvents.count))")
                    .font(.headline)
                Spacer()
                if let msg = viewModel.calendarSyncStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if filteredEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: category.systemImage)
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No \(category.displayName) Events Shown")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        allCategoryEvents.isEmpty
                            ? "Add an event to \(category.displayName), import a RenWeb grade report, or attach an .ics calendar feed."
                            : "No events match the selected date or filter."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                    HStack(spacing: 10) {
                        if viewModel.calendarSelectedDay != nil || viewModel.calendarTimeFilter != .all || !viewModel.calendarSearchQuery.isEmpty {
                            Button("Show All \(category.displayName) Events") {
                                viewModel.calendarSelectedDay = nil
                                viewModel.calendarTimeFilter = .all
                                viewModel.calendarSearchQuery = ""
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("Add \(category.displayName) Event") {
                            viewModel.openNewCalendarEventSheet(for: category)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredEvents) { event in
                        CalendarEventRowView(
                            event: event,
                            tint: tint,
                            canDelete: viewModel.state.calendarEvents.contains(where: { $0.id == event.id && $0.source == .manual }),
                            onToggleComplete: {
                                viewModel.toggleCalendarEventCompletion(event)
                            },
                            onDelete: {
                                viewModel.deleteCalendarEvent(event)
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Month Calendar Grid View

private struct CalendarMonthGridView: View {
    let category: FamilyPortalCalendarCategory
    let events: [CalendarEvent]
    let tint: Color
    @ObservedObject var viewModel: SchoolTrackerViewModel

    private let calendar = Calendar.current
    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: viewModel.calendarDisplayedMonth)
    }

    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: viewModel.calendarDisplayedMonth),
              let daysRange = calendar.range(of: .day, in: .month, for: viewModel.calendarDisplayedMonth)
        else { return [] }

        let firstDayWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyCount = max(0, firstDayWeekday - 1)
        var slots: [Date?] = Array(repeating: nil, count: leadingEmptyCount)

        for dayOffset in 0..<daysRange.count {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: monthInterval.start) {
                slots.append(date)
            }
        }
        return slots
    }

    private func eventCount(on date: Date) -> Int {
        events.filter { calendar.isDate($0.startDate, inSameDayAs: date) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(monthTitle)
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        viewModel.shiftDisplayedMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Today") {
                        viewModel.jumpToCurrentMonth()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        viewModel.shiftDisplayedMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, maybeDate in
                    if let date = maybeDate {
                        let count = eventCount(on: date)
                        let isSelected = viewModel.calendarSelectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        let isToday = calendar.isDateInToday(date)

                        Button {
                            if isSelected {
                                viewModel.calendarSelectedDay = nil
                            } else {
                                viewModel.calendarSelectedDay = date
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.caption.monospacedDigit().weight(isToday || isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? .white : (isToday ? tint : .primary))

                                Circle()
                                    .fill(count > 0 ? (isSelected ? Color.white : tint) : Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(
                                isSelected
                                    ? tint
                                    : (isToday ? tint.opacity(0.12) : Color.clear),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 32)
                    }
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Calendar Event Row View

private struct CalendarEventRowView: View {
    let event: CalendarEvent
    let tint: Color
    let canDelete: Bool
    let onToggleComplete: () -> Void
    let onDelete: () -> Void

    private var sourceLabel: String {
        switch event.source {
        case .icalFeed:
            return "iCal Feed"
        case .importedReport:
            return "RenWeb Sync"
        case .manual:
            return "Manual"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleComplete) {
                Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(event.isCompleted ? .green : tint)
            }
            .buttonStyle(.plain)
            .help("Toggle completion status")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .strikethrough(event.isCompleted)
                        .foregroundStyle(event.isCompleted ? .secondary : .primary)

                    if let courseName = event.courseName, !courseName.isEmpty {
                        Text(courseName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.14), in: Capsule())
                            .foregroundStyle(tint)
                    }

                    Text(sourceLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Label(
                        event.isAllDay
                            ? event.startDate.formatted(date: .abbreviated, time: .omitted) + " · All Day"
                            : event.startDate.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "calendar"
                    )
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete event")
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - New Calendar Event Sheet

struct NewCalendarEventSheet: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let category = viewModel.activeCalendarEventCategory
        let tint = SchoolTrackerViewModel.calendarCategoryTint(for: category)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New \(category.displayName) Event")
                        .font(.title3.weight(.bold))
                    Text("Adds an event directly to the \(category.displayName) calendar space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Event Title", text: $viewModel.draftEventTitle, prompt: Text("e.g., Robotics Club Meeting or Chapter 6 Exam"))

                Picker("Space", selection: $viewModel.activeCalendarEventCategory) {
                    ForEach(FamilyPortalCalendarCategory.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }

                if category != .school {
                    TextField("Course / Classroom (Optional)", text: $viewModel.draftEventCourseName, prompt: Text("e.g., AP Calculus BC"))
                }

                Toggle("All-Day Event", isOn: $viewModel.draftEventIsAllDay)
                DatePicker(
                    "Date",
                    selection: $viewModel.draftEventStartDate,
                    displayedComponents: viewModel.draftEventIsAllDay ? [.date] : [.date, .hourAndMinute]
                )

                TextField("Location (Optional)", text: $viewModel.draftEventLocation, prompt: Text("e.g., Room 204 or Main Auditorium"))
                TextField("Notes (Optional)", text: $viewModel.draftEventNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)

            if let error = viewModel.draftEventValidationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Event") {
                    if viewModel.saveDraftCalendarEvent() {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Runtime App Icon Renderer

enum SchoolTrackerAppIcon {
    @MainActor
    static func applyRuntimeDockIconIfNeeded() {
        // If bundled with AppIcon.icns in Contents/Resources, macOS loads it automatically;
        // when launched directly via `swift run SchoolTrackerApp`, synthesize the same squircle icon.
        if Bundle.main.path(forResource: "AppIcon", ofType: "icns") != nil {
            return
        }
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let insetRect = rect.insetBy(dx: 28, dy: 28)
            let cornerRadius: CGFloat = 104
            let path = NSBezierPath(roundedRect: insetRect, xRadius: cornerRadius, yRadius: cornerRadius)

            ctx.saveGState()
            path.addClip()

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.42, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.82, alpha: 1.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: insetRect.minX, y: insetRect.maxY),
                    end: CGPoint(x: insetRect.maxX, y: insetRect.minY),
                    options: []
                )
            }
            ctx.restoreGState()

            NSColor.white.withAlphaComponent(0.22).setStroke()
            path.lineWidth = 6
            path.stroke()

            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 210, weight: .bold)
            if let symbol = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) {
                let symSize = symbol.size
                let drawRect = NSRect(
                    x: rect.midX - symSize.width / 2,
                    y: rect.midY - symSize.height / 2 + 24,
                    width: symSize.width,
                    height: symSize.height
                )
                symbol.draw(in: drawRect)
            }
            return true
        }
        NSApplication.shared.applicationIconImage = image
    }
}
