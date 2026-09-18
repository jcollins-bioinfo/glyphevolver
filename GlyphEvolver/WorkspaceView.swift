import SwiftUI
import UIKit
import GlyphCore

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        TabView {
            NavigationStack { EvolveView(model:model) }.tabItem { Label("Evolve",systemImage:"sparkles") }
            NavigationStack { LineageView(model:model) }.tabItem { Label("Lineage",systemImage:"point.3.connected.trianglepath.dotted") }
            NavigationStack { SettingsView(model:model) }.tabItem { Label("Settings",systemImage:"slider.horizontal.3") }
            NavigationStack { AboutView(catalog:model.catalog) }.tabItem { Label("About",systemImage:"info.circle") }
        }.tint(.indigo)
    }
}
struct EvolveView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:6) {
                    Text(model.run.name).font(.subheadline).foregroundStyle(.secondary)
                    Text("Three seeds.\nUnexpected possibilities.").font(.largeTitle.bold())
                    Text("Explore one recognizable form, transformed by three ideas.").foregroundStyle(.secondary)
                }
                if let candidate=model.candidate {
                    let columns = [GridItem(.adaptive(minimum:typeSize.isAccessibilitySize ? 240 : 95),spacing:12)]
                    LazyVGrid(columns:columns,spacing:12) {
                        ForEach(Array(candidate.conceptIDs.enumerated()),id:\.offset) { slot,id in
                            let concept=model.catalog.concepts[id]
                            VStack(spacing:12) {
                                Text(concept.canonicalGlyph).font(.system(size:56)).accessibilityHidden(true)
                                Text(concept.canonicalName).font(.headline).multilineTextAlignment(.center)
                                Button {
                                    if model.pins.contains(slot) { model.pins.remove(slot) } else { model.pins.insert(slot) }
                                } label: {
                                    Label(model.pins.contains(slot) ? "Pinned" : "Pin",systemImage:model.pins.contains(slot) ? "pin.fill" : "pin")
                                        .font(.caption).frame(minHeight:44)
                                }.accessibilityLabel("\(model.pins.contains(slot) ? "Unpin" : "Pin") \(concept.canonicalName)")
                            }.frame(maxWidth:.infinity,minHeight:190).padding(10)
                                .background(.indigo.opacity(0.08),in:RoundedRectangle(cornerRadius:24))
                        }
                    }
                    VStack(alignment:.leading,spacing:8) {
                        Label("Composition intent",systemImage:"wand.and.stars").font(.headline)
                        ForEach(Array(candidate.score.bestRoleAssignment.conceptIDs.enumerated()),id:\.offset) { i,id in
                            Text("\(model.catalog.concepts[id].canonicalName.capitalized) · \(candidate.score.bestRoleAssignment.template.roles[i].rawValue)")
                        }
                    }.font(.subheadline)
                }
                if let error=model.error { Label(error,systemImage:"exclamationmark.circle").foregroundStyle(.red) }
                Button(action:model.search) {
                    HStack { if model.searching { ProgressView() }; Text(model.candidate==nil ? "Find a combination" : "Prepare another combination") }.frame(maxWidth:.infinity,minHeight:44)
                }.buttonStyle(.borderedProminent).disabled(model.searching)
                VStack(alignment:.leading,spacing:8) {
                    Label("Native generation is not connected yet",systemImage:"hammer").font(.headline)
                    Text("This development build lets you explore seed combinations. Creating and accepting adaptive glyphs requires the iOS 27 Image Playground integration, which has not been built or verified with the available SDK.")
                }.font(.subheadline).padding().background(.quaternary,in:RoundedRectangle(cornerRadius:16))
                Text("Your seed reproduces GlyphEvolver’s input choices, not Apple’s generated images.").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Evolve").navigationBarTitleDisplayMode(.inline)
            .task { if model.candidate==nil { model.search() } }
    }
}
struct LineageView: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        Group {
            if model.nodes.isEmpty {
                ContentUnavailableView("Your lineage begins with an accepted glyph",systemImage:"leaf",description:Text("Prepared combinations are not saved as generated glyphs. Native creation is pending iOS 27 integration."))
            } else {
                List(model.nodes) { node in
                    NavigationLink {
                        Form {
                            Text(node.contentDescription)
                            Text("Generation \(node.generationIndex)")
                            Text(node.createdAt,style:.date)
                            Button("Branch from Here") { model.selectParent(node) }
                            Button("Copy Description") { UIPasteboard.general.string=node.contentDescription }
                            ForEach(GenerationFeedback.allCases,id:\.rawValue) { rating in
                                Button("Rate: \(String(describing:rating))") {
                                    do { try model.store.feedback(node:node,rating:rating) } catch { model.error=error.localizedDescription }
                                }
                            }
                        }.navigationTitle("Generation \(node.generationIndex)")
                    } label: {
                        VStack(alignment:.leading) {
                            Text("Generation \(node.generationIndex)").font(.headline)
                            Text(node.contentDescription)
                            if let parent=node.parentID { Text("Parent \(parent.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }.navigationTitle("Lineage")
    }
}
