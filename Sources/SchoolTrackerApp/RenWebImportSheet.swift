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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temporary Report Link (`GetReport.cfm`)")
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
                    .disabled(viewModel.importState.isBusy)
                }

                TextField(placeholderURL, text: $viewModel.importURLInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(viewModel.importState.isBusy)

                liveValidationIndicator
            }

            stateCalloutSection

            securityFootnote

            Divider()

            footerButtons
        }
        .padding(24)
        .frame(width: 560)
    }

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import FACTS / RenWeb Email Report")
                    .font(.title3.weight(.bold))
                Text("Paste the temporary GetReport.cfm link from your school progress report email.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
                    Text("Imported \(courseCount) courses and \(assignmentCount) assignments (\(district))")
                        .font(.callout.weight(.semibold))
                    Text("Grades saved to local Application Support with SessionID redacted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text("Import Failed")
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
            Text("Security: Ephemeral non-caching URLSession. Raw SessionID tokens and HTML are never logged or committed.")
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
            .disabled(viewModel.importState.isBusy)

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
                    Label("Fetch & Import Grades", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.importState.isBusy ||
                    viewModel.importURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
