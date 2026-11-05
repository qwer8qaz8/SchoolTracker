import Foundation

// MARK: - Local Persistence Store (~/Library/Application Support/SchoolTracker/state.json, saved-link.json & saved-calendars.json)

public enum PersistenceError: Error, Equatable, LocalizedError, Sendable {
    case readFailed(reason: String)
    case decodeFailed(reason: String)
    case writeFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .readFailed(let reason):
            return "Failed to read local state file: \(reason)"
        case .decodeFailed(let reason):
            return "Failed to decode local state JSON: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write local state file: \(reason)"
        }
    }
}

private struct StoredRenWebLinkCredential: Codable, Equatable, Sendable {
    var urlString: String
    var district: String
    var sessionID: String
    var savedAt: Date
    var expiresAt: Date
}

private struct StoredCalendarFeedCredentialRecord: Codable, Equatable, Sendable {
    var categoryRawValue: String
    var urlString: String
    var updatedAt: Date
}

private struct StoredCalendarsCredentialFile: Codable, Equatable, Sendable {
    var feeds: [StoredCalendarFeedCredentialRecord]
    var updatedAt: Date
}

public final class SchoolTrackerStore: @unchecked Sendable {
    public let stateFileURL: URL
    public let savedLinkCredentialFileURL: URL
    public let savedCalendarsCredentialFileURL: URL
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        stateFileURL: URL = SchoolTrackerStore.defaultStateFileURL(),
        savedLinkCredentialFileURL: URL? = nil,
        savedCalendarsCredentialFileURL: URL? = nil
    ) {
        self.stateFileURL = stateFileURL
        let baseDir = stateFileURL.deletingLastPathComponent()
        self.savedLinkCredentialFileURL = savedLinkCredentialFileURL
            ?? baseDir.appendingPathComponent("saved-link.json", isDirectory: false)
        self.savedCalendarsCredentialFileURL = savedCalendarsCredentialFileURL
            ?? baseDir.appendingPathComponent("saved-calendars.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Resolves `~/Library/Application Support/SchoolTracker/state.json`.
    public static func defaultStateFileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("SchoolTracker", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    /// Resolves `~/Library/Application Support/SchoolTracker/saved-link.json`.
    public static func defaultSavedLinkCredentialFileURL() -> URL {
        defaultStateFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("saved-link.json", isDirectory: false)
    }

    /// Resolves `~/Library/Application Support/SchoolTracker/saved-calendars.json`.
    public static func defaultSavedCalendarsCredentialFileURL() -> URL {
        defaultStateFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("saved-calendars.json", isDirectory: false)
    }

    public func loadState() throws -> SchoolTrackerState {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            let empty = SchoolTrackerState()
            SchoolTrackerTelemetry.shared.increment(.stateLoadSuccess, context: "initialized_empty_state")
            return empty
        }

        let data: Data
        do {
            data = try Data(contentsOf: stateFileURL)
        } catch {
            SchoolTrackerTelemetry.shared.increment(.stateLoadFailure, context: "io_read_error")
            throw PersistenceError.readFailed(reason: error.localizedDescription)
        }

        do {
            let state = try decoder.decode(SchoolTrackerState.self, from: data)
            SchoolTrackerTelemetry.shared.increment(
                .stateLoadSuccess,
                context: "courses=\(state.courses.count) tasks=\(state.tasks.count) calendarEvents=\(state.calendarEvents.count)"
            )
            return state
        } catch {
            SchoolTrackerTelemetry.shared.increment(.stateLoadFailure, context: "json_decode_error")
            throw PersistenceError.decodeFailed(reason: error.localizedDescription)
        }
    }

    public func saveState(_ state: SchoolTrackerState) throws {
        lock.lock()
        defer { lock.unlock() }

        var sanitizedState = state
        if let rawURL = sanitizedState.lastRedactedReportURL {
            sanitizedState.lastRedactedReportURL = SchoolTrackerTelemetry.redactSensitiveTokens(in: rawURL)
        }
        if var savedLink = sanitizedState.savedLink {
            savedLink.redactedURL = SchoolTrackerTelemetry.redactSensitiveTokens(in: savedLink.redactedURL)
            sanitizedState.savedLink = savedLink
        }
        sanitizedState.calendarSubscriptions = sanitizedState.calendarSubscriptions.map { sub in
            var copy = sub
            if let rawFeedURL = copy.redactedFeedURL {
                copy.redactedFeedURL = SchoolTrackerTelemetry.redactSensitiveTokens(in: rawFeedURL)
            }
            return copy
        }

        let directoryURL = stateFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try encoder.encode(sanitizedState)
            try data.write(to: stateFileURL, options: [.atomic])
            SchoolTrackerTelemetry.shared.increment(
                .stateSaveSuccess,
                context: "courses=\(sanitizedState.courses.count) tasks=\(sanitizedState.tasks.count) calendarEvents=\(sanitizedState.calendarEvents.count)"
            )
        } catch {
            SchoolTrackerTelemetry.shared.increment(.stateSaveFailure, context: "io_write_error")
            throw PersistenceError.writeFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Saved Temporary RenWeb Link Credential Store

    @discardableResult
    public func saveRenWebLink(
        _ link: ValidatedRenWebLink,
        savedAt: Date = Date(),
        expiresAt: Date? = nil,
        lastVerifiedAt: Date? = nil
    ) throws -> SavedRenWebLink {
        lock.lock()
        defer { lock.unlock() }

        let effectiveExpiresAt = expiresAt ?? savedAt.addingTimeInterval(SavedRenWebLink.defaultTTL)
        let effectiveVerifiedAt = lastVerifiedAt ?? savedAt

        try writeLinkCredentialFile(
            link: link,
            savedAt: savedAt,
            expiresAt: effectiveExpiresAt
        )

        let metadata = SavedRenWebLink(
            district: link.district,
            redactedURL: link.redactedDescription,
            savedAt: savedAt,
            expiresAt: effectiveExpiresAt,
            lastVerifiedAt: effectiveVerifiedAt,
            isConfirmedExpired: false
        )

        var state = (try? loadState()) ?? SchoolTrackerState()
        state.savedLink = metadata
        state.lastSyncedDistrict = link.district
        state.lastRedactedReportURL = link.redactedDescription
        try saveState(state)

        SchoolTrackerTelemetry.shared.increment(
            .savedLinkSaveSuccess,
            context: "district=\(link.district) link=\(link.redactedDescription)"
        )
        return metadata
    }

    public func loadSavedRenWebLink() throws -> ValidatedRenWebLink? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: savedLinkCredentialFileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: savedLinkCredentialFileURL)
        } catch {
            SchoolTrackerTelemetry.shared.increment(.savedLinkLoadFailure, context: "io_read_error")
            throw PersistenceError.readFailed(reason: error.localizedDescription)
        }

        let credential: StoredRenWebLinkCredential
        do {
            credential = try decoder.decode(StoredRenWebLinkCredential.self, from: data)
        } catch {
            SchoolTrackerTelemetry.shared.increment(.savedLinkLoadFailure, context: "json_decode_error")
            throw PersistenceError.decodeFailed(reason: error.localizedDescription)
        }

        do {
            let link = try RenWebLinkParser.parse(credential.urlString)
            SchoolTrackerTelemetry.shared.increment(.savedLinkLoadSuccess, context: link.redactedDescription)
            return link
        } catch {
            SchoolTrackerTelemetry.shared.increment(.savedLinkLoadFailure, context: "invalid_stored_url")
            throw PersistenceError.decodeFailed(reason: error.localizedDescription)
        }
    }

    @discardableResult
    public func markSavedLinkExpired(at date: Date = Date()) throws -> SavedRenWebLink? {
        lock.lock()
        defer { lock.unlock() }

        var state = try loadState()
        guard var savedLink = state.savedLink else {
            return nil
        }
        savedLink.isConfirmedExpired = true
        savedLink.lastVerifiedAt = date
        state.savedLink = savedLink
        try saveState(state)

        SchoolTrackerTelemetry.shared.increment(
            .savedLinkMarkedExpired,
            context: "district=\(savedLink.district) link=\(savedLink.redactedURL)"
        )
        return savedLink
    }

    public func clearSavedRenWebLink() throws {
        lock.lock()
        defer { lock.unlock() }

        if FileManager.default.fileExists(atPath: savedLinkCredentialFileURL.path) {
            do {
                try FileManager.default.removeItem(at: savedLinkCredentialFileURL)
            } catch {
                SchoolTrackerTelemetry.shared.increment(.savedLinkSaveFailure, context: "remove_credential_failed")
                throw PersistenceError.writeFailed(reason: error.localizedDescription)
            }
        }

        if FileManager.default.fileExists(atPath: stateFileURL.path) {
            var state = try loadState()
            state.savedLink = nil
            try saveState(state)
        }

        SchoolTrackerTelemetry.shared.increment(.savedLinkCleared, context: "cleared_saved_link")
    }

    @discardableResult
    public func applyImportedReport(
        _ report: ImportedGradeReport,
        from link: ValidatedRenWebLink? = nil,
        syncedAt: Date = Date()
    ) throws -> SchoolTrackerState {
        lock.lock()
        defer { lock.unlock() }

        var state = (try? loadState()) ?? SchoolTrackerState()
        state.courses = Self.mergeCourses(existing: state.courses, imported: report.courses)
        state.lastSyncedAt = syncedAt

        if let link {
            state.lastSyncedDistrict = link.district
            state.lastRedactedReportURL = link.redactedDescription

            let existingCredential = try? loadStoredCredentialRecord()
            let isSameSession = existingCredential?.sessionID == link.sessionID
                && existingCredential?.district.caseInsensitiveCompare(link.district) == .orderedSame

            let effectiveSavedAt = (isSameSession ? (state.savedLink?.savedAt ?? existingCredential?.savedAt) : nil) ?? syncedAt
            let effectiveExpiresAt = report.expiresAt
                ?? (isSameSession ? (state.savedLink?.expiresAt ?? existingCredential?.expiresAt) : nil)
                ?? effectiveSavedAt.addingTimeInterval(SavedRenWebLink.defaultTTL)

            try writeLinkCredentialFile(
                link: link,
                savedAt: effectiveSavedAt,
                expiresAt: effectiveExpiresAt
            )

            state.savedLink = SavedRenWebLink(
                district: link.district,
                redactedURL: link.redactedDescription,
                savedAt: effectiveSavedAt,
                expiresAt: effectiveExpiresAt,
                lastVerifiedAt: syncedAt,
                isConfirmedExpired: false
            )
        }

        try saveState(state)
        return state
    }

    // MARK: - Family Portal Calendar Subscriptions & .ics Feed Persistence

    @discardableResult
    public func updateCalendarSubscriptions(
        selectedCategories: Set<FamilyPortalCalendarCategory>,
        feedURLStrings: [FamilyPortalCalendarCategory: String] = [:],
        updatedAt: Date = Date()
    ) throws -> SchoolTrackerState {
        lock.lock()
        defer { lock.unlock() }

        guard !selectedCategories.isEmpty else {
            SchoolTrackerTelemetry.shared.increment(
                .calendarSubscriptionUpdateFailure,
                context: "empty_selected_categories"
            )
            throw FamilyPortalCalendarError.atLeastOneCategoryRequired
        }

        var validatedFeeds: [FamilyPortalCalendarCategory: ValidatedCalendarFeedLink] = (try? loadSavedCalendarFeedLinks()) ?? [:]
        for (category, rawString) in feedURLStrings {
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                validatedFeeds.removeValue(forKey: category)
            } else {
                let parsed = try FamilyPortalCalendarLinkParser.parse(trimmed, for: category)
                validatedFeeds[category] = parsed
            }
        }

        try writeCalendarsCredentialFile(feeds: validatedFeeds, updatedAt: updatedAt)

        var state = (try? loadState()) ?? SchoolTrackerState()
        let existingByCategory = Dictionary(
            uniqueKeysWithValues: state.calendarSubscriptions.map { ($0.category, $0) }
        )

        state.calendarSubscriptions = FamilyPortalCalendarCategory.allCases.map { category in
            let previous = existingByCategory[category]
            let redactedURL = validatedFeeds[category]?.redactedDescription
                ?? (feedURLStrings[category]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
                    ? nil
                    : previous?.redactedFeedURL)
            return FamilyPortalCalendarSubscription(
                category: category,
                isSubscribed: selectedCategories.contains(category),
                redactedFeedURL: redactedURL,
                lastSyncedAt: previous?.lastSyncedAt
            )
        }

        try saveState(state)
        SchoolTrackerTelemetry.shared.increment(
            .calendarSubscriptionUpdateSuccess,
            context: "subscribed=\(selectedCategories.map(\.rawValue).sorted().joined(separator: ","))"
        )
        return state
    }

    public func loadSavedCalendarFeedLinks() throws -> [FamilyPortalCalendarCategory: ValidatedCalendarFeedLink] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: savedCalendarsCredentialFileURL.path) else {
            return [:]
        }

        let data: Data
        do {
            data = try Data(contentsOf: savedCalendarsCredentialFileURL)
        } catch {
            throw PersistenceError.readFailed(reason: error.localizedDescription)
        }

        let credentialFile: StoredCalendarsCredentialFile
        do {
            credentialFile = try decoder.decode(StoredCalendarsCredentialFile.self, from: data)
        } catch {
            throw PersistenceError.decodeFailed(reason: error.localizedDescription)
        }

        var result: [FamilyPortalCalendarCategory: ValidatedCalendarFeedLink] = [:]
        for entry in credentialFile.feeds {
            guard let category = FamilyPortalCalendarCategory(rawValue: entry.categoryRawValue) else {
                continue
            }
            if let validated = try? FamilyPortalCalendarLinkParser.parse(entry.urlString, for: category) {
                result[category] = validated
            }
        }
        return result
    }

    @discardableResult
    public func applyCalendarICS(
        _ ics: String,
        for category: FamilyPortalCalendarCategory,
        syncedAt: Date = Date()
    ) throws -> SchoolTrackerState {
        lock.lock()
        defer { lock.unlock() }

        let parsedEvents = try FamilyPortalICalendarParser.parse(ics: ics, category: category)
        var state = (try? loadState()) ?? SchoolTrackerState()

        let existingCategoryFeedEvents = state.calendarEvents.filter {
            $0.category == category && $0.source == .icalFeed
        }
        let retainedEvents = state.calendarEvents.filter {
            $0.category != category || $0.source != .icalFeed
        }

        var usedIDs = Set<UUID>()
        let mergedFeedEvents: [CalendarEvent] = parsedEvents.map { incoming in
            var merged = incoming
            if let match = existingCategoryFeedEvents.first(where: { candidate in
                guard !usedIDs.contains(candidate.id) else { return false }
                if let incomingUID = incoming.uid, let candidateUID = candidate.uid, !incomingUID.isEmpty {
                    return incomingUID == candidateUID
                }
                return candidate.title.caseInsensitiveCompare(incoming.title) == .orderedSame
                    && candidate.startDate == incoming.startDate
            }) {
                usedIDs.insert(match.id)
                merged.id = match.id
                merged.isCompleted = match.isCompleted
            }
            return merged
        }

        state.calendarEvents = retainedEvents + mergedFeedEvents

        if let subIndex = state.calendarSubscriptions.firstIndex(where: { $0.category == category }) {
            state.calendarSubscriptions[subIndex].lastSyncedAt = syncedAt
        } else {
            state.calendarSubscriptions.append(
                FamilyPortalCalendarSubscription(
                    category: category,
                    isSubscribed: true,
                    redactedFeedURL: nil,
                    lastSyncedAt: syncedAt
                )
            )
        }

        try saveState(state)
        return state
    }

    @discardableResult
    public func addCalendarEvent(_ event: CalendarEvent) throws -> SchoolTrackerState {
        lock.lock()
        defer { lock.unlock() }

        var state = (try? loadState()) ?? SchoolTrackerState()
        state.calendarEvents.append(event)
        try saveState(state)
        return state
    }

    @discardableResult
    public func toggleCalendarEventCompletion(_ eventID: UUID) throws -> SchoolTrackerState {
        lock.lock()
        defer { lock.unlock() }

        var state = (try? loadState()) ?? SchoolTrackerState()
        if let index = state.calendarEvents.firstIndex(where: { $0.id == eventID }) {
            state.calendarEvents[index].isCompleted.toggle()
            try saveState(state)
        }
        return state
    }

    @discardableResult
    public func deleteCalendarEvent(_ eventID: UUID) throws -> SchoolTrackerState {
        lock.lock()
        defer { lock.unlock() }

        var state = (try? loadState()) ?? SchoolTrackerState()
        state.calendarEvents.removeAll { $0.id == eventID }
        try saveState(state)
        return state
    }

    private func loadStoredCredentialRecord() throws -> StoredRenWebLinkCredential? {
        guard FileManager.default.fileExists(atPath: savedLinkCredentialFileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: savedLinkCredentialFileURL)
        return try decoder.decode(StoredRenWebLinkCredential.self, from: data)
    }

    private func writeLinkCredentialFile(
        link: ValidatedRenWebLink,
        savedAt: Date,
        expiresAt: Date
    ) throws {
        let directoryURL = savedLinkCredentialFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let credential = StoredRenWebLinkCredential(
                urlString: link.url.absoluteString,
                district: link.district,
                sessionID: link.sessionID,
                savedAt: savedAt,
                expiresAt: expiresAt
            )
            let data = try encoder.encode(credential)
            try data.write(to: savedLinkCredentialFileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: savedLinkCredentialFileURL.path
            )
        } catch {
            SchoolTrackerTelemetry.shared.increment(.savedLinkSaveFailure, context: "credential_io_write_error")
            throw PersistenceError.writeFailed(reason: error.localizedDescription)
        }
    }

    private func writeCalendarsCredentialFile(
        feeds: [FamilyPortalCalendarCategory: ValidatedCalendarFeedLink],
        updatedAt: Date
    ) throws {
        let directoryURL = savedCalendarsCredentialFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let records = FamilyPortalCalendarCategory.allCases.compactMap { category -> StoredCalendarFeedCredentialRecord? in
                guard let link = feeds[category] else { return nil }
                return StoredCalendarFeedCredentialRecord(
                    categoryRawValue: category.rawValue,
                    urlString: link.url.absoluteString,
                    updatedAt: updatedAt
                )
            }
            let payload = StoredCalendarsCredentialFile(feeds: records, updatedAt: updatedAt)
            let data = try encoder.encode(payload)
            try data.write(to: savedCalendarsCredentialFileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: savedCalendarsCredentialFileURL.path
            )
        } catch {
            SchoolTrackerTelemetry.shared.increment(
                .calendarSubscriptionUpdateFailure,
                context: "calendar_credential_io_write_error"
            )
            throw PersistenceError.writeFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Re-Import Course & Assignment Merging

    private static func mergeCourses(
        existing: [ImportedCourse],
        imported: [ImportedCourse]
    ) -> [ImportedCourse] {
        var usedExistingCourseIDs = Set<UUID>()

        return imported.map { incoming in
            var mergedCourse = incoming
            if let matchedCourse = findMatchingCourse(
                for: incoming,
                in: existing,
                excluding: usedExistingCourseIDs
            ) {
                usedExistingCourseIDs.insert(matchedCourse.id)
                mergedCourse.id = matchedCourse.id
                mergedCourse.categories = mergeCategories(
                    existing: matchedCourse.categories,
                    imported: incoming.categories
                )
                mergedCourse.assignments = mergeAssignments(
                    existing: matchedCourse.assignments,
                    imported: incoming.assignments
                )
            }
            return mergedCourse
        }
    }

    private static func findMatchingCourse(
        for incoming: ImportedCourse,
        in existing: [ImportedCourse],
        excluding usedIDs: Set<UUID>
    ) -> ImportedCourse? {
        let incomingCode = incoming.courseCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !incomingCode.isEmpty {
            if let matchByCode = existing.first(where: { candidate in
                guard !usedIDs.contains(candidate.id),
                      let candidateCode = candidate.courseCode?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !candidateCode.isEmpty
                else { return false }
                return candidateCode.caseInsensitiveCompare(incomingCode) == .orderedSame
            }) {
                return matchByCode
            }
        }

        let incomingName = incoming.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.first { candidate in
            guard !usedIDs.contains(candidate.id) else { return false }
            let candidateName = candidate.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            return candidateName.caseInsensitiveCompare(incomingName) == .orderedSame
        }
    }

    private static func mergeCategories(
        existing: [CategoryBreakdown],
        imported: [CategoryBreakdown]
    ) -> [CategoryBreakdown] {
        var usedIDs = Set<UUID>()
        return imported.map { incoming in
            var merged = incoming
            if let match = existing.first(where: { candidate in
                !usedIDs.contains(candidate.id)
                    && candidate.name.caseInsensitiveCompare(incoming.name) == .orderedSame
            }) {
                usedIDs.insert(match.id)
                merged.id = match.id
            }
            return merged
        }
    }

    private static func mergeAssignments(
        existing: [ImportedAssignment],
        imported: [ImportedAssignment]
    ) -> [ImportedAssignment] {
        var usedIDs = Set<UUID>()
        return imported.map { incoming in
            var merged = incoming
            if let match = findMatchingAssignment(
                for: incoming,
                in: existing,
                excluding: usedIDs
            ) {
                usedIDs.insert(match.id)
                merged.id = match.id
                merged.isCompleted = match.isCompleted
            }
            return merged
        }
    }

    private static func findMatchingAssignment(
        for incoming: ImportedAssignment,
        in existing: [ImportedAssignment],
        excluding usedIDs: Set<UUID>
    ) -> ImportedAssignment? {
        let incomingTitle = incoming.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingCategory = incoming.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingDue = incoming.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let exactMatch = existing.first(where: { candidate in
            guard !usedIDs.contains(candidate.id) else { return false }
            let candidateDue = candidate.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(incomingTitle) == .orderedSame
                && candidate.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(incomingCategory) == .orderedSame
                && candidateDue.caseInsensitiveCompare(incomingDue) == .orderedSame
        }) {
            return exactMatch
        }

        return existing.first { candidate in
            guard !usedIDs.contains(candidate.id) else { return false }
            return candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(incomingTitle) == .orderedSame
                && candidate.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(incomingCategory) == .orderedSame
        }
    }
}
