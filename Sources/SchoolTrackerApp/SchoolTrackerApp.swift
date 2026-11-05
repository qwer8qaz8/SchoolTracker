import SwiftUI
import SchoolTrackerCore

@main
struct SchoolTrackerApp: App {
    @StateObject private var viewModel = SchoolTrackerViewModel()

    var body: some Scene {
        WindowGroup("SchoolTracker") {
            RootSplitView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    SchoolTrackerAppIcon.applyRuntimeDockIconIfNeeded()
                    viewModel.loadInitialState()
                }
        }
        .defaultSize(width: 1140, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import or Manage RenWeb Link…") {
                    viewModel.openImportSheet()
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Subscribe to Family Portal Calendars…") {
                    viewModel.openCalendarSubscriptionSheet()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Sync Saved RenWeb Link") {
                    if viewModel.hasSavedLink {
                        Task {
                            await viewModel.syncSavedLink()
                        }
                    } else {
                        viewModel.openImportSheet()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.isSyncingSavedLink)

                Button("New Task…") {
                    viewModel.isPresentingNewTaskSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Reload Local State") {
                    viewModel.loadInitialState()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
