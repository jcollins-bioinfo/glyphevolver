import SwiftUI
import GlyphCore

@main struct GlyphEvolverApp: App {
    var body: some Scene {
        WindowGroup { AppRoot() }
    }
}
struct AppRoot: View {
    @State private var model: WorkspaceModel?
    @State private var failure: String?
    var body: some View {
        Group {
            if let model { WorkspaceView(model:model) }
            else if let failure {
                ContentUnavailableView { Label("Unable to open your workspace",systemImage:"externaldrive.badge.exclamationmark") }
                    description: { Text(failure) } actions: { Button("Try Again") { load() } }
            } else { ProgressView("Opening GlyphEvolver…") }
        }.task { if model==nil { load() } }
    }
    private func load() {
        do { model=try WorkspaceModel(); failure=nil } catch { failure=error.localizedDescription }
    }
}
