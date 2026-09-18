import Foundation
import Observation
import OSLog
import GlyphCore

@MainActor @Observable final class WorkspaceModel {
    let catalog: EmojiCatalog
    let store: LineageStore
    var run: EvolutionRun
    var settings: EvolutionSettings
    var candidate: SearchCandidate?
    var pins: Set<Int> = []
    var nodes: [GenerationNode] = []
    var error: String?
    var searching=false
    private var searchTask: Task<Void,Never>?
    private var searchID=UUID()
    private let log=Logger(subsystem:"GlyphEvolver",category:"evolution")
    init() throws {
        catalog=try EmojiCatalog.bundled(); store=try LineageStore()
        if let existing=try store.runs().first {
            guard existing.catalogVersion==catalog.version else { throw SearchError.invalidCatalog }
            run=existing; settings=try JSONDecoder().decode(EvolutionSettings.self,from:existing.settingsData)
        }
        else {
            settings=EvolutionSettings()
            run=try store.createRun(name:"First explorations",seed:UInt64.random(in:UInt64.min...UInt64.max),catalogVersion:catalog.version,settings:settings)
        }
        nodes=try store.nodes(runID:run.id)
    }
    func search() {
        guard !searching else { return }
        do {
            try saveSettings()
            let engine=TripletSearchEngine(catalog:catalog), config=settings
            let history=try store.history(runID:run.id,catalogVersion:catalog.version)
            let preferences=try store.preferenceModel(), pins=pins
            let parent=candidate?.conceptIDs
            guard let seed=UInt64(run.rngState) else { throw SearchError.invalidSettings }
            let id=UUID(); searchID=id; searching=true; error=nil
            searchTask=Task {
                let result = await Task.detached(priority:.userInitiated) { () -> Result<(SearchCandidate,UInt64),Error> in
                    do {
                        var rng=SplitMix64(seed:seed)
                        let next=try engine.select(settings:config,parent:parent,pins:pins,history:history,preferences:preferences,rng:&rng)
                        return .success((next,rng.state))
                    } catch { return .failure(error) }
                }.value
                guard !Task.isCancelled, self.searchID==id else { return }
                self.searching=false
                guard self.settings==config else { self.error="Settings changed during selection. Prepare another combination."; return }
                switch result {
                case .success(let (next,state)):
                    self.candidate=next; self.run.rngState=String(state)
                    do { try self.store.save() } catch { self.error=error.localizedDescription }
                    self.log.info("Prepared a candidate using local search")
                case .failure(let failure): self.error=failure.localizedDescription
                }
            }
        } catch { self.error=error.localizedDescription }
    }
    func saveSettings() throws { run.settingsData=try JSONEncoder().encode(settings); try store.save() }
    func newRun(seed: UInt64) {
        searchTask?.cancel(); searchID=UUID(); searching=false
        do {
            run=try store.createRun(name:"Exploration \((try store.runs()).count+1)",seed:seed,catalogVersion:catalog.version,settings:settings)
            candidate=nil; pins=[]; nodes=[]; search()
        } catch { self.error=error.localizedDescription }
    }
    func selectParent(_ node: GenerationNode) {
        do {
            run.activeNodeID=node.id; candidate=try JSONDecoder().decode(SearchCandidate.self,from:node.candidateData)
            try store.feedback(node:node,signal:.branchedFrom); pins=[]
        } catch { self.error=error.localizedDescription }
    }
}
