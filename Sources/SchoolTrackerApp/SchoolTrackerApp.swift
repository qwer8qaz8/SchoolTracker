import SwiftUI
import SchoolTrackerCore

@main
struct SchoolTrackerApp: App {
    @StateObject private var viewModel = SchoolTrackerViewModel()

    var body: some Scene {
        WindowGroup("SchoolTracker") {
            RootSplitView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    viewModel.loadInitialState()
                }
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import RenWeb Link…") {
                    viewModel.openImportSheet()
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("New Task…") {
                    viewModel.isPresentingNewTaskSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Reload Local State") {
                    viewModel.loadInitialState()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
