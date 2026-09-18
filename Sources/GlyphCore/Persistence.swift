#if canImport(SwiftData)
import Foundation
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1,0,0) }
    public static var models: [any PersistentModel.Type] { [EvolutionRun.self,GenerationNode.self,SeenTriplet.self,FeedbackRecord.self,PreferenceSnapshot.self] }
    @Model public final class EvolutionRun {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var createdAt: Date
        public var modifiedAt: Date
        public var rootNodeID: UUID?
        public var activeNodeID: UUID?
        public var seed: String
        public var rngState: String
        public var catalogVersion: String
        public var settingsData: Data
        public init(name: String, seed: UInt64, catalogVersion: String, settings: EvolutionSettings) throws {
            let now=Date()
            id=UUID(); self.name=name; createdAt=now; modifiedAt=now
            self.seed=String(seed); rngState=String(seed); self.catalogVersion=catalogVersion
            settingsData=try JSONEncoder().encode(settings)
        }
    }
    @Model public final class GenerationNode {
        @Attribute(.unique) public var id: UUID
        public var runID: UUID
        public var branchID: UUID
        public var parentID: UUID?
        public var secondParentID: UUID?
        public var generationIndex: Int
        public var createdAt: Date
        public var tripletRank: String
        public var catalogVersion: String
        public var exactPrompt: String
        public var contentIdentifier: String
        public var contentDescription: String
        public var candidateData: Data
        public var settingsData: Data
        public var phenotypeData: Data
        @Attribute(.externalStorage) public var imageContent: Data
        public init(id: UUID, runID: UUID, parentID: UUID?, branchID: UUID, generationIndex: Int,
                    candidate: SearchCandidate, settings: EvolutionSettings, prompt: String, phenotype: Phenotype,
                    imageContent: Data, contentIdentifier: String, contentDescription: String) throws {
            self.id=id; self.runID=runID; self.parentID=parentID; self.branchID=branchID
            self.generationIndex=generationIndex; createdAt=Date(); tripletRank=String(candidate.tripletID.rawValue)
            catalogVersion=candidate.catalogVersion; exactPrompt=prompt
            self.contentIdentifier=contentIdentifier; self.contentDescription=contentDescription; self.imageContent=imageContent
            candidateData=try JSONEncoder().encode(candidate); settingsData=try JSONEncoder().encode(settings)
            phenotypeData=try JSONEncoder().encode(phenotype)
        }
    }
    @Model public final class SeenTriplet {
        @Attribute(.unique) public var key: String
        public var runID: UUID
        public var catalogVersion: String
        public var rank: String
        public init(runID: UUID, catalogVersion: String, rank: String) {
            self.runID=runID; self.catalogVersion=catalogVersion; self.rank=rank
            key="\(catalogVersion)|\(runID.uuidString)|\(rank)"
        }
    }
    @Model public final class FeedbackRecord {
        @Attribute(.unique) public var nodeID: UUID
        public var runID: UUID
        public var rating: Int?
        public var signalsData: Data
        public var updatedAt: Date
        public init(nodeID: UUID, runID: UUID) {
            self.nodeID=nodeID; self.runID=runID; signalsData=Data("[]".utf8); updatedAt=Date()
        }
    }
    @Model public final class PreferenceSnapshot {
        @Attribute(.unique) public var key: String
        public var modelVersion: String
        public var data: Data
        public var updatedAt: Date
        public init(data: Data) {
            key="local"; modelVersion=PreferenceModel.version; self.data=data; updatedAt=Date()
        }
    }
}
public enum GlyphMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
public typealias EvolutionRun = SchemaV1.EvolutionRun
public typealias GenerationNode = SchemaV1.GenerationNode

/// Single MainActor writer is the acceptance/uniqueness boundary for this local-only app.
@MainActor public final class LineageStore {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }
    public init(inMemory: Bool = false) throws {
        container=try ModelContainer(for:Schema(versionedSchema:SchemaV1.self),migrationPlan:GlyphMigrationPlan.self,
            configurations:[ModelConfiguration(isStoredInMemoryOnly:inMemory,cloudKitDatabase:.none)])
        context.autosaveEnabled=false
    }
    public func runs() throws -> [EvolutionRun] { try context.fetch(FetchDescriptor<EvolutionRun>(sortBy:[SortDescriptor(\.modifiedAt,order:.reverse)])) }
    public func nodes(runID: UUID) throws -> [GenerationNode] {
        try context.fetch(FetchDescriptor<GenerationNode>(predicate:#Predicate { $0.runID==runID },sortBy:[SortDescriptor(\.createdAt)]))
    }
    public func createRun(name: String, seed: UInt64, catalogVersion: String, settings: EvolutionSettings) throws -> EvolutionRun {
        let run=try EvolutionRun(name:name,seed:seed,catalogVersion:catalogVersion,settings:settings)
        context.insert(run); try save(); return run
    }
    public func history(runID: UUID, catalogVersion: String) throws -> SearchHistory {
        var result=SearchHistory()
        for entry in try context.fetch(FetchDescriptor<SchemaV1.SeenTriplet>(predicate:#Predicate { $0.catalogVersion==catalogVersion })) {
            guard let raw=UInt64(entry.rank) else { continue }
            let id=TripletID(rawValue:raw); result.allSeen.insert(id)
            if entry.runID==runID { result.runSeen.insert(id) }
        }
        result.recentGenerations=try nodes(runID:runID).suffix(100).map { try JSONDecoder().decode(SearchCandidate.self,from:$0.candidateData).conceptIDs }
        return result
    }
    @discardableResult public func accept(_ node: GenerationNode, run: EvolutionRun, rngState: UInt64, scope: NoRepeatScope) throws -> Bool {
        let id=node.id
        guard try context.fetchCount(FetchDescriptor<GenerationNode>(predicate:#Predicate { $0.id==id }))==0 else { return false }
        guard node.runID==run.id, node.catalogVersion==run.catalogVersion, !node.imageContent.isEmpty,
              !node.contentIdentifier.isEmpty, let rank=UInt64(node.tripletRank) else { throw SearchError.invalidTriplet }
        let existing=try nodes(runID:run.id)
        if let parentID=node.parentID {
            guard let parent=existing.first(where: { $0.id==parentID }), node.generationIndex==parent.generationIndex+1 else { throw SearchError.invalidTriplet }
        } else if !existing.isEmpty || node.generationIndex != 0 { throw SearchError.invalidTriplet }
        let history=try history(runID:run.id,catalogVersion:run.catalogVersion)
        guard !history.seen(for:scope).contains(.init(rawValue:rank)) else { throw SearchError.exhausted }
        context.insert(node)
        if !history.runSeen.contains(.init(rawValue:rank)) {
            context.insert(SchemaV1.SeenTriplet(runID:run.id,catalogVersion:run.catalogVersion,rank:node.tripletRank))
        }
        run.activeNodeID=node.id; if run.rootNodeID==nil { run.rootNodeID=node.id }
        run.rngState=String(rngState); run.modifiedAt=Date()
        try save(); return true
    }
    public func deleteRun(_ run: EvolutionRun) throws {
        let id=run.id
        for node in try nodes(runID:id) { context.delete(node) }
        for entry in try context.fetch(FetchDescriptor<SchemaV1.SeenTriplet>(predicate:#Predicate { $0.runID==id })) { context.delete(entry) }
        for feedback in try context.fetch(FetchDescriptor<SchemaV1.FeedbackRecord>(predicate:#Predicate { $0.runID==id })) { context.delete(feedback) }
        context.delete(run); _ = try rebuildPreferences(); try save()
    }
    public func feedback(node: GenerationNode, rating: GenerationFeedback? = nil, signal: BehavioralSignal? = nil) throws {
        let id=node.id
        let record=try context.fetch(FetchDescriptor<SchemaV1.FeedbackRecord>(predicate:#Predicate { $0.nodeID==id })).first
            ?? SchemaV1.FeedbackRecord(nodeID:id,runID:node.runID)
        context.insert(record)
        if let rating { record.rating=rating.rawValue }
        if let signal {
            var signals=try JSONDecoder().decode([BehavioralSignal].self,from:record.signalsData)
            signals.append(signal); record.signalsData=try JSONEncoder().encode(signals)
        }
        record.updatedAt=Date()
        _ = try rebuildPreferences()
        try save()
    }
    public func preferenceModel() throws -> PreferenceModel {
        if let snapshot=try context.fetch(FetchDescriptor<SchemaV1.PreferenceSnapshot>()).first,
           snapshot.modelVersion==PreferenceModel.version {
            var model=try JSONDecoder().decode(PreferenceModel.self,from:snapshot.data)
            model.validateSchema()
            if model.trainingSampleCount>0 { return model }
        }
        let model=try rebuildPreferences(); try save(); return model
    }
    private func rebuildPreferences() throws -> PreferenceModel {
        let feedback=try context.fetch(FetchDescriptor<SchemaV1.FeedbackRecord>())
        let nodes=try context.fetch(FetchDescriptor<GenerationNode>())
        let byID=Dictionary(uniqueKeysWithValues:nodes.map { ($0.id,$0) })
        var examples:[PreferenceExample]=[]
        for record in feedback {
            if let raw=record.rating, let rating=GenerationFeedback(rawValue:raw), let node=byID[record.nodeID] {
                let candidate=try JSONDecoder().decode(SearchCandidate.self,from:node.candidateData)
                examples.append(.init(nodeID:node.id,features:candidate.score.features,feedback:rating))
            }
        }
        var model=PreferenceModel(); model.train(examples)
        let data=try JSONEncoder().encode(model)
        if let snapshot=try context.fetch(FetchDescriptor<SchemaV1.PreferenceSnapshot>()).first {
            snapshot.data=data; snapshot.updatedAt=Date(); snapshot.modelVersion=PreferenceModel.version
        } else { context.insert(SchemaV1.PreferenceSnapshot(data:data)) }
        return model
    }
    public func resetPreferences() throws {
        for record in try context.fetch(FetchDescriptor<SchemaV1.FeedbackRecord>()) { context.delete(record) }
        for snapshot in try context.fetch(FetchDescriptor<SchemaV1.PreferenceSnapshot>()) { context.delete(snapshot) }
        try save()
    }
    public func exportMetadata(run: EvolutionRun) throws -> Data {
        struct Feedback: Codable { let nodeID: UUID; let explicitRating: Int?; let behavioralSignals: [BehavioralSignal]; let updatedAt: Date }
        struct Node: Codable {
            let id, branchID: UUID
            let parentID, secondParentID: UUID?
            let generationIndex: Int
            let createdAt: Date
            let candidate: SearchCandidate
            let settings: EvolutionSettings
            let phenotype: Phenotype
            let prompt, contentIdentifier, contentDescription: String
        }
        struct Export: Codable {
            let formatVersion: Int
            let runID: UUID
            let runSeed, rngState, catalogVersion: String
            let nodes: [Node]
            let feedback: [Feedback]
            let preferenceModel: PreferenceModel
        }
        let decoder=JSONDecoder(), runID=run.id
        let nodes=try nodes(runID:runID).map { node in
            Node(id:node.id,branchID:node.branchID,parentID:node.parentID,secondParentID:node.secondParentID,
                generationIndex:node.generationIndex,createdAt:node.createdAt,
                candidate:try decoder.decode(SearchCandidate.self,from:node.candidateData),
                settings:try decoder.decode(EvolutionSettings.self,from:node.settingsData),
                phenotype:try decoder.decode(Phenotype.self,from:node.phenotypeData),prompt:node.exactPrompt,
                contentIdentifier:node.contentIdentifier,contentDescription:node.contentDescription)
        }
        let feedback=try context.fetch(FetchDescriptor<SchemaV1.FeedbackRecord>(predicate:#Predicate { $0.runID==runID })).map {
            Feedback(nodeID:$0.nodeID,explicitRating:$0.rating,behavioralSignals:try decoder.decode([BehavioralSignal].self,from:$0.signalsData),updatedAt:$0.updatedAt)
        }
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Export(formatVersion:1,runID:runID,runSeed:run.seed,rngState:run.rngState,catalogVersion:run.catalogVersion,
            nodes:nodes,feedback:feedback,preferenceModel:preferenceModel()))
    }
    public func save() throws {
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
#endif
