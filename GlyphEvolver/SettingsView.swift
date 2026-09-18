import SwiftUI
import GlyphCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: WorkspaceModel
    @State private var seed=""
    @State private var reset=false
    @State private var export: MetadataDocument?
    @State private var exporting=false
    var body: some View {
        Form {
            Section("Search") {
                Picker("Sampling mode",selection:$model.settings.regime) {
                    Text("Strict Curated").tag(SamplingRegime.strictCurated)
                    Text("Exploratory").tag(SamplingRegime.exploratory)
                    Text("Wild").tag(SamplingRegime.wild)
                }
                Text("Strict Curated favors one transformed entity. Exploratory allows broader compositions. Wild keeps validity and your exclusions, with minimal composition filtering.").font(.caption)
                LabeledContent("Novelty",value:model.settings.novelty.formatted(.percent.precision(.fractionLength(0))))
                Slider(value:$model.settings.novelty,in:0...1).accessibilityLabel("Novelty")
                Picker("No-repeat scope",selection:$model.settings.noRepeat) {
                    Text("None").tag(NoRepeatScope.none); Text("Current run").tag(NoRepeatScope.currentRun); Text("All history").tag(NoRepeatScope.allHistory)
                }
                Toggle("Learn from explicit ratings",isOn:$model.settings.preferenceLearning)
                NavigationLink("Aesthetic exclusions") {
                    Form { ForEach(["waste","illness","injury","weapons","medical","insects","food","faces","humans","religion","death"],id:\.self) { tag in
                        Toggle(tag.capitalized,isOn:Binding(get:{ model.settings.excludedTags.contains(tag) },set:{ value in
                            if value { model.settings.excludedTags.insert(tag) } else { model.settings.excludedTags.remove(tag) }
                        }))
                    } }.navigationTitle("Excluded concepts")
                }
            }
            Section("Evolution search") {
                Toggle("Mutate the previous prepared seeds",isOn:$model.settings.evolution)
                Picker("Mutation",selection:$model.settings.mutation) {
                    Text("Random").tag(MutationStrategy.random); Text("Semantic Near").tag(MutationStrategy.semanticNear)
                    Text("Semantic Far").tag(MutationStrategy.semanticFar); Text("Category Shift").tag(MutationStrategy.categoryShift)
                }
                Stepper("Mutate \(model.settings.mutationCount) seeds",value:$model.settings.mutationCount,in:0...3)
                Slider(value:$model.settings.mutationStrength,in:0...1) { Text("Mutation strength") }
                Text("More strength broadens Semantic Near and intensifies Semantic Far. Pinned slots never change; impossible combinations show an error.").font(.caption)
                Stepper("Exclude the last \(model.settings.recentWindow) accepted generations",value:$model.settings.recentWindow,in:0...30)
                Toggle("Include complex emoji sequences",isOn:$model.settings.includeZWJ)
            }
            Section("Reproducibility") {
                LabeledContent("Run seed",value:model.run.seed).textSelection(.enabled)
                TextField("New run seed (unsigned integer)",text:$seed).keyboardType(.numberPad)
                Button("Start New Run") {
                    if let value=UInt64(seed) { model.newRun(seed:value) }
                    else { model.error="Enter an unsigned 64-bit integer to start a seeded run." }
                }.disabled(UInt64(seed)==nil)
            }
            Section("Advanced") {
                NavigationLink("Triplet Search") {
                    Form {
                        LabeledContent("Strict threshold",value:"0.70")
                        LabeledContent("Candidate pool",value:"64")
                        LabeledContent("Exploration",value:"10%")
                        LabeledContent("Scoring model",value:"heuristic-1")
                        LabeledContent("Catalog",value:model.catalog.version)
                        Text("Heuristic scores describe input composability. They do not measure the quality of an unseen generated image.")
                    }.navigationTitle("Triplet Search")
                }
                Button("Reset Learned Preferences",role:.destructive) { reset=true }
                Button("Export Run Metadata") {
                    do { export=MetadataDocument(data:try model.store.exportMetadata(run:model.run)); exporting=true }
                    catch { model.error=error.localizedDescription }
                }
            }
            Button("Save Settings") { do { try model.saveSettings() } catch { model.error=error.localizedDescription } }
        }.navigationTitle("Settings")
            .fileExporter(isPresented:$exporting,document:export,contentType:.json,defaultFilename:"glyphevolver-metadata") { result in
                if case .failure(let error)=result { model.error=error.localizedDescription }
            }
            .confirmationDialog("Reset all local ratings and behavioral history?",isPresented:$reset,titleVisibility:.visible) {
                Button("Reset Preferences",role:.destructive) { do { try model.store.resetPreferences() } catch { model.error=error.localizedDescription } }
            }
    }
}
struct MetadataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data=data }
    init(configuration: ReadConfiguration) throws { data=configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct AboutView: View {
    let catalog: EmojiCatalog
    var body: some View {
        Form {
            Section("GlyphEvolver") {
                Text("An interactive search for strange but visually composable emoji combinations.")
                Text("Development foundation · native creation pending")
                Text("The intended native flow uses Apple’s system Image Playground interface. Every generated adaptive glyph must be reviewed and accepted by you in the system sheet on a supported device.")
            }
            Section("On this device") {
                Text("The implemented search and preference engine runs locally. There is no account, backend, analytics SDK, or remote model service in this build.")
                Text("Explicit ratings and interaction records remain in the local store. No cloud synchronization is configured.")
            }
            Section("Search space") {
                LabeledContent("Raw emoji entries",value:"\(catalog.raw.count)")
                LabeledContent("Canonical concepts",value:"\(catalog.concepts.count)")
                if let space=try? choose(UInt64(catalog.concepts.count),3) { LabeledContent("Unordered triples",value:space.formatted()) }
                Text("Strict Curated searches a dynamically filtered subset of the full combination space.")
            }
            Section("Acknowledgments") {
                Text("Unicode data and CLDR annotations © Unicode, Inc. See the repository’s third-party notices.")
                Text("GlyphEvolver is independent and is not affiliated with or endorsed by Apple. Genmoji is an Apple trademark.")
                LabeledContent("Version",value:"\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1") (\(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1"))")
            }
        }.navigationTitle("About")
    }
}
