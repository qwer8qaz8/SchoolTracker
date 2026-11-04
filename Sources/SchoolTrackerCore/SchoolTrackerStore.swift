import Foundation

// MARK: - Local Persistence Store (~/Library/Application Support/SchoolTracker/state.json & saved-link.json)

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

public final class SchoolTrackerStore: @unchecked Sendable {
    public let stateFileURL: URL
    public let savedLinkCredentialFileURL: URL
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        stateFileURL: URL = SchoolTrackerStore.defaultStateFileURL(),
        savedLinkCredentialFileURL: URL? = nil
    ) {
        self.stateFileURL = stateFileURL
        self.savedLinkCredentialFileURL = savedLinkCredentialFileURL
            ?? stateFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("saved-link.json", isDirectory: false)

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
                context: "courses=\(state.courses.count) tasks=\(state.tasks.count)"
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
                context: "courses=\(sanitizedState.courses.count) tasks=\(sanitizedState.tasks.count)"
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
