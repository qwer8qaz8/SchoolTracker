import Foundation

// MARK: - Local Persistence Store (~/Library/Application Support/SchoolTracker/state.json)

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

public final class SchoolTrackerStore: @unchecked Sendable {
    public let stateFileURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stateFileURL: URL = SchoolTrackerStore.defaultStateFileURL()) {
        self.stateFileURL = stateFileURL

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

    @discardableResult
    public func applyImportedReport(
        _ report: ImportedGradeReport,
        from link: ValidatedRenWebLink? = nil,
        syncedAt: Date = Date()
    ) throws -> SchoolTrackerState {
        var state = (try? loadState()) ?? SchoolTrackerState()
        state.courses = report.courses
        state.lastSyncedAt = syncedAt
        if let link {
            state.lastSyncedDistrict = link.district
            state.lastRedactedReportURL = link.redactedDescription
        }
        try saveState(state)
        return state
    }
}
