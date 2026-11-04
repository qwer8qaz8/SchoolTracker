import AppKit
import SwiftUI
import SchoolTrackerCore

struct RenWebImportSheet: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel
    @Environment(\.dismiss) private var dismiss

    private let placeholderURL = "https://example.client.factsmgt.com/renweb/email/GetReport.cfm?District=TEST-XX&SessionID=00000000-0000-0000-0000-000000000000"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader

            if let savedLink = viewModel.state.savedLink {
                savedLinkSection(savedLink)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.hasSavedLink ? "Replace Saved Link (`GetReport.cfm`)" : "Temporary Report Link (`GetReport.cfm`)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button {
                        if let pasted = NSPasteboard.general.string(forType: .string) {
                            viewModel.importURLInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.importState.isBusy || viewModel.isSyncingSavedLink)
                }

                TextField(placeholderURL, text: $viewModel.importURLInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(viewModel.importState.isBusy || viewModel.isSyncingSavedLink)

                liveValidationIndicator
            }

            stateCalloutSection

            securityFootnote

            Divider()

            footerButtons
        }
        .padding(24)
        .frame(width: 580)
    }

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved FACTS / RenWeb Report Link")
                    .font(.title3.weight(.bold))
                Text("Save your temporary GetReport.cfm email link to track when it expires and sync grades in one click.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func savedLinkSection(_ savedLink: SavedRenWebLink) -> some View {
        let status = savedLink.expirationStatus()
        let statusColor = SchoolTrackerViewModel.expirationStatusColor(for: status)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: SchoolTrackerViewModel.expirationStatusIcon(for: status))
                    .foregroundStyle(statusColor)
                Text("Current Saved Link · District \(savedLink.district)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(savedLink.expirationSummaryText())
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Text(savedLink.redactedURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                Text("Saved \(savedLink.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Expires \(savedLink.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task {
                        await viewModel.syncSavedLink()
                    }
                } label: {
                    Label(
                        viewModel.isSyncingSavedLink ? "Syncing…" : "Sync Saved Link Now",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.importState.isBusy || viewModel.isSyncingSavedLink)

                Button(role: .destructive) {
                    viewModel.clearSavedLink()
                } label: {
                    Label("Clear Link", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.importState.isBusy || viewModel.isSyncingSavedLink)
            }
        }
        .padding(12)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var liveValidationIndicator: some View {
        if let preview = viewModel.liveLinkPreview {
            switch preview {
            case .success(let validated):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Valid HTTPS link · District: \(validated.district) · Redacted: \(validated.redactedDescription)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            case .failure(let error):
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Requires an HTTPS *.factsmgt.com or *.renweb.com link containing District and SessionID parameters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateCalloutSection: some View {
        switch viewModel.importState {
        case .idle:
            EmptyView()

        case .validating:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Validating FACTS/RenWeb URL parameters and redaction rules…")
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

        case .fetching(let redactedURL, let district):
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fetching grade report for district \(district)…")
                        .font(.callout.weight(.medium))
                    Text(redactedURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

        case .success(let courseCount, let assignmentCount, let district):
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Synced \(courseCount) courses and \(assignmentCount) assignments (\(district))")
                        .font(.callout.weight(.semibold))
                    if let summary = viewModel.savedLinkExpirationSummary {
                        Text("Link saved in app · \(summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Grades and link saved to local Application Support with SessionID redacted in state.json.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

        case .failure(let reason):
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sync / Import Failed")
                        .font(.callout.weight(.semibold))
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") {
                    viewModel.resetImportSheet()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var securityFootnote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Security: Saved locally in owner-only saved-link.json (0600); state.json and logs always mask SessionID=REDACTED.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(viewModel.importState.isBusy || viewModel.isSyncingSavedLink)

            Spacer()

            if case .success = viewModel.importState {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    Task {
                        await viewModel.importFromRenWebLink()
                    }
                } label: {
                    Label("Save Link & Import Grades", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.importState.isBusy ||
                    viewModel.isSyncingSavedLink ||
                    viewModel.importURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
