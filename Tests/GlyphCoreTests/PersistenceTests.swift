import XCTest
import SwiftData
@testable import GlyphCore

final class PersistenceTests: XCTestCase {
    @MainActor func testAcceptanceBranchingSnapshotsFeedbackAndDeletion() throws {
        let store=try LineageStore(inMemory:true), catalog=try EmojiCatalog.bundled()
        var settings=EvolutionSettings(); settings.regime = .wild; settings.noRepeat = .none
        let run=try store.createRun(name:"Test",seed:42,catalogVersion:catalog.version,settings:settings)
        var rng=SplitMix64(seed:42)
        let candidate=try TripletSearchEngine(catalog:catalog).select(settings:settings,rng:&rng)
        func node(parent: GenerationNode? = nil) throws -> GenerationNode {
            try GenerationNode(id:UUID(),runID:run.id,parentID:parent?.id,branchID:UUID(),generationIndex:parent.map { $0.generationIndex+1 } ?? 0,
                candidate:candidate,settings:settings,prompt:"fixture",phenotype:.init(dominantSubjects:[],visualTraits:[],semanticTraits:[],tone:"test",provenance:"synthetic-test"),
                imageContent:Data([1,2,3]),contentIdentifier:"synthetic-test-only",contentDescription:"test fixture")
        }
        let root=try node()
        XCTAssertTrue(try store.accept(root,run:run,rngState:rng.state,scope:.currentRun))
        XCTAssertFalse(try store.accept(root,run:run,rngState:rng.state,scope:.currentRun))
        XCTAssertThrowsError(try store.accept(node(parent:root),run:run,rngState:rng.state,scope:.currentRun))
        let a=try node(parent:root), b=try node(parent:root)
        XCTAssertTrue(try store.accept(a,run:run,rngState:rng.state,scope:.none))
        XCTAssertTrue(try store.accept(b,run:run,rngState:rng.state,scope:.none))
        XCTAssertEqual(try store.nodes(runID:run.id).count,3)
        XCTAssertEqual(a.parentID,root.id); XCTAssertEqual(b.parentID,root.id)
        let original=root.settingsData; settings.novelty=0.99
        XCTAssertEqual(root.settingsData,original)
        let reload=ModelContext(store.container)
        XCTAssertEqual(try reload.fetch(FetchDescriptor<GenerationNode>()).count,3)
        XCTAssertEqual(try store.history(runID:run.id,catalogVersion:catalog.version).runSeen.count,1)
        try store.feedback(node:root,rating:.good,signal:.branchedFrom)
        let record=try XCTUnwrap(store.context.fetch(FetchDescriptor<SchemaV1.FeedbackRecord>()).first)
        XCTAssertEqual(record.rating,1)
        XCTAssertEqual(try JSONDecoder().decode([BehavioralSignal].self,from:record.signalsData),[.branchedFrom])
        let export=try store.exportMetadata(run:run)
        let exported=try XCTUnwrap(JSONSerialization.jsonObject(with:export) as? [String:Any])
        XCTAssertEqual((exported["nodes"] as? [[String:Any]])?.count,3)
        XCTAssertFalse(String(decoding:export,as:UTF8.self).contains("imageContent"))
        try store.deleteRun(run)
        XCTAssertTrue(try store.runs().isEmpty)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<GenerationNode>()),0)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<SchemaV1.SeenTriplet>()),0)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<SchemaV1.FeedbackRecord>()),0)
    }
}
