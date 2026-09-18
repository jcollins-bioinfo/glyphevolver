import XCTest
@testable import GlyphCore

final class CoreTests: XCTestCase {
    func testCombinadicExhaustiveThreeThroughThirty() throws {
        for n in 3...30 {
            var seen: Set<UInt64> = []
            for a in 0..<(n-2) { for b in (a+1)..<(n-1) { for c in (b+1)..<n {
                let id = try TripletID(conceptIDs:(a,b,c))
                XCTAssertTrue(seen.insert(id.rawValue).inserted)
                let decoded = try conceptIDs(for:id,catalogSize:n)
                XCTAssertEqual([decoded.0,decoded.1,decoded.2],[a,b,c])
                for p in [(a,b,c),(a,c,b),(b,a,c),(b,c,a),(c,a,b),(c,b,a)] {
                    XCTAssertEqual(try TripletID(conceptIDs:p),id)
                }
                XCTAssertEqual(try TripletID(conceptIDs:decoded),id)
            } } }
            XCTAssertEqual(seen.count,Int(try choose(UInt64(n),3)))
            XCTAssertEqual(seen.min(),0)
            XCTAssertEqual(seen.max(),try choose(UInt64(n),3)-1)
        }
    }
    func testCombinadicInvalidAndOverflow() throws {
        XCTAssertThrowsError(try TripletID(conceptIDs:(1,1,2)))
        XCTAssertThrowsError(try TripletID(conceptIDs:(-1,1,2)))
        XCTAssertThrowsError(try choose(UInt64.max,3))
        XCTAssertThrowsError(try conceptIDs(for:.init(rawValue:1),catalogSize:3))
        XCTAssertEqual(try choose(2,3),0)
        XCTAssertEqual(try choose(0,0),1)
    }
    func testPRNGReferenceVectorAndWeights() {
        var r = SplitMix64(seed:0)
        XCTAssertEqual(r.next(),0xe220a8397b1dcdaf)
        XCTAssertEqual(r.next(),0x6e789e6aa1b965f4)
        XCTAssertNil(r.weightedIndex([0,0]))
        XCTAssertNil(r.weightedIndex([.nan,1]))
        for _ in 0..<100 { XCTAssertEqual(r.weightedIndex([0,5,0]),1) }
    }
    func testCatalogIntegrity() throws {
        let catalog = try EmojiCatalog.bundled()
        XCTAssertEqual(catalog.raw.count,3944)
        XCTAssertEqual(catalog.concepts.map(\.id),Array(catalog.concepts.indices))
        XCTAssertEqual(Set(catalog.concepts.flatMap(\.rawEmojiIDs)),Set(catalog.raw.map(\.id)))
        XCTAssertEqual(catalog.concepts.flatMap(\.rawEmojiIDs).count,catalog.raw.count)
        XCTAssertTrue(catalog.raw.contains { $0.isZWJSequence })
        let scientist=try XCTUnwrap(catalog.concepts.first { $0.canonicalName=="scientist" })
        let scientists=catalog.raw.filter { scientist.rawEmojiIDs.contains($0.id) }
        XCTAssertTrue(scientists.contains { $0.shortName=="woman scientist" })
        XCTAssertTrue(scientists.contains { $0.shortName=="man scientist" })
        XCTAssertTrue(scientists.contains { $0.shortName=="scientist" })
        for c in catalog.concepts {
            XCTAssertTrue(catalog.raw.contains { c.rawEmojiIDs.contains($0.id) && $0.glyph==c.canonicalGlyph })
            XCTAssertTrue(GenerativeRole.allCases.allSatisfy { (0...1).contains(c.roles[$0]) })
        }
    }
    func testQualityFixtures() throws {
        let cat = try EmojiCatalog.bundled(), scorer = TripletScorer()
        func concepts(_ names: [String]) throws -> [EmojiConcept] {
            try names.map { name in try XCTUnwrap(cat.concepts.first { $0.canonicalName==name },name) }
        }
        for fixture in [["butterfly","brain","crescent moon"],["octopus","musical keyboard","milky way"],
                        ["owl","eye","key"],["castle","ice","rose"],["cat","fire","sparkles"]] {
            let result = try scorer.evaluate(concepts(fixture))
            XCTAssertTrue(result.accepted,"\(fixture): \(result.reasons) \(result.score.total)")
        }
        let faces = try concepts(["grinning face","grinning face with big eyes","grinning face with smiling eyes"])
        XCTAssertTrue(try scorer.evaluate(faces).reasons.contains(.threeFaces))
        let arrows = Array(cat.concepts.filter { $0.subgroup=="arrow" }.prefix(3))
        XCTAssertTrue(try scorer.evaluate(arrows).reasons.contains(.excludedConcept))
        let clocks = Array(cat.concepts.filter { $0.subgroup=="time" }.prefix(3))
        XCTAssertFalse(try scorer.evaluate(clocks).accepted)
        let humans = Array(cat.concepts.filter { $0.isHuman && $0.isZWJSequence }.prefix(3))
        XCTAssertTrue(try scorer.evaluate(humans).reasons.contains(.threeHumanCharacters))
    }
    func testReproducibleSelectionAndHistory() throws {
        let cat = try EmojiCatalog.bundled(), engine = TripletSearchEngine(catalog:cat)
        var a = SplitMix64(seed:42), b = a, history = SearchHistory()
        var settings = EvolutionSettings(); settings.evolution=false
        for _ in 0..<5 {
            let x = try engine.select(settings:settings,history:history,rng:&a)
            let y = try engine.select(settings:settings,history:history,rng:&b)
            XCTAssertEqual(x.tripletID,y.tripletID)
            XCTAssertEqual(x.conceptIDs,y.conceptIDs)
            XCTAssertEqual(x.score,y.score)
            XCTAssertTrue(history.runSeen.insert(x.tripletID).inserted)
            history.recentGenerations.append(x.conceptIDs)
            XCTAssertGreaterThanOrEqual(x.score.total,0.70)
        }
    }
    func testMutationPinsAndExhaustion() throws {
        let cat = try EmojiCatalog.bundled(), engine = TripletSearchEngine(catalog:cat)
        var rng = SplitMix64(seed:100), settings = EvolutionSettings()
        settings.regime = .wild; settings.excludedTags=[]; settings.noRepeat = .none
        let parent = [0,1,2]
        for count in 0...3 {
            settings.mutationCount=count
            let c = try engine.select(settings:settings,parent:parent,rng:&rng)
            XCTAssertEqual(zip(c.conceptIDs,parent).filter { $0 != $1 }.count,count)
            XCTAssertEqual(Set(c.conceptIDs).count,3)
        }
        settings.mutationCount=2
        let child = try engine.select(settings:settings,parent:parent,pins:[1],rng:&rng)
        XCTAssertEqual(child.conceptIDs[1],parent[1])
        XCTAssertThrowsError(try engine.select(settings:settings,parent:parent,pins:[0,1],rng:&rng))
        settings.allowedGroups=["nonexistent"]
        XCTAssertThrowsError(try engine.select(settings:settings,rng:&rng))
    }
    func testNoRepeatCannotBeOverriddenAndScopes() throws {
        let cat = try EmojiCatalog.bundled(), c = Array(cat.concepts.filter { $0.defaultEligibility == .strict }.prefix(3))
        let id = try TripletID(conceptIDs:(c[0].id,c[1].id,c[2].id))
        var settings = EvolutionSettings(); settings.regime = .wild
        XCTAssertTrue(try TripletScorer().evaluate(c,settings:settings,seen:[id]).reasons.contains(.duplicate))
        var h = SearchHistory(); h.allSeen=[id]
        XCTAssertTrue(h.seen(for:.currentRun).isEmpty)
        XCTAssertEqual(h.seen(for:.allHistory),[id])
        XCTAssertTrue(h.seen(for:.none).isEmpty)
    }
    func testNoveltyZeroAndRecentPenalty() throws {
        let cat = try EmojiCatalog.bundled(), c = Array(cat.concepts.prefix(3)), scorer = TripletScorer()
        var settings = EvolutionSettings(); settings.novelty=0
        XCTAssertEqual(try scorer.evaluate(c,settings:settings).score.novelty,try scorer.evaluate(c,settings:settings,recent:Set(c.map(\.id))).score.novelty)
        settings.novelty=1
        XCTAssertGreaterThan(try scorer.evaluate(c,settings:settings).score.novelty,try scorer.evaluate(c,settings:settings,recent:Set(c.map(\.id))).score.novelty)
    }
    func testPreferenceGateDirectionsResetAndSchema() throws {
        let features = [Double](repeating:0.5,count:18)
        var model = PreferenceModel()
        let positive = (0..<12).map { _ in PreferenceExample(features:features,feedback:.good) }
        model.train(Array(positive.prefix(11))); XCTAssertNil(model.predict(features))
        model.train(positive); XCTAssertGreaterThan(try XCTUnwrap(model.predict(features)),0.5)
        model.train((0..<12).map { _ in PreferenceExample(features:features,feedback:.poor) })
        XCTAssertLessThan(try XCTUnwrap(model.predict(features)),0.5)
        XCTAssertTrue(model.coefficients.allSatisfy(\.isFinite))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(model)) as? [String:Any])
        json["schema"]="future"
        model = try JSONDecoder().decode(PreferenceModel.self,from:JSONSerialization.data(withJSONObject:json))
        model.validateSchema(); XCTAssertNil(model.predict(features)); XCTAssertEqual(model.trainingSampleCount,0)
        model.train(positive); model.reset(); XCTAssertTrue(model.coefficients.allSatisfy { $0==0 })
    }
    func testCoordinatorExactlyOnceAndDismissalBarrier() throws {
        var c = GenerationCoordinator(); let id=UUID()
        XCTAssertTrue(c.prepare(id:id)); XCTAssertTrue(c.present(id)); XCTAssertFalse(c.present(id))
        XCTAssertFalse(c.accept(UUID())); XCTAssertTrue(c.accept(id)); XCTAssertFalse(c.accept(id))
        XCTAssertTrue(c.beginPersistence(id)); XCTAssertTrue(c.didPersist(id)); XCTAssertFalse(c.didPersist(id))
        XCTAssertFalse(c.advance(id,autoAdvance:true,limit:nil,foreground:true))
        c.didDismiss(id)
        XCTAssertFalse(c.advance(id,autoAdvance:true,limit:nil,foreground:false))
        XCTAssertTrue(c.advance(id,autoAdvance:true,limit:nil,foreground:true))
        XCTAssertFalse(c.advance(id,autoAdvance:true,limit:nil,foreground:true))
        XCTAssertEqual(c.completed,1)
        XCTAssertTrue(c.prepare()); XCTAssertFalse(c.accept(id))
    }
    func testCoordinatorCancellationFailureLimitAndStop() {
        for ending in 0...3 {
            var c=GenerationCoordinator(); let id=UUID()
            c.prepare(id:id); _ = c.present(id)
            if ending==0 { c.cancel(id) }
            else if ending==1 { c.fail(id) }
            else { _ = c.accept(id); _ = c.beginPersistence(id); _ = c.didPersist(id) }
            if ending==3 { c.stop() }
            c.didDismiss(id)
            XCTAssertFalse(c.advance(id,autoAdvance:true,limit:ending==2 ? 1 : nil,foreground:true))
        }
    }
    func testPromptRespectsInheritance() throws {
        let cat = try EmojiCatalog.bundled(), seeds = Array(cat.concepts.prefix(3))
        let roles=RoleAssignment(template:.subjectFeatureSetting,conceptIDs:seeds.map(\.id))
        var settings=EvolutionSettings(); let builder=GenerationPromptBuilder()
        XCTAssertTrue(builder.build(seeds:seeds,parentDescription:"ancestor",settings:settings,roles:roles).contains("ancestor"))
        settings.evolution=false
        let prompt=builder.build(seeds:seeds,parentDescription:"ancestor",settings:settings,roles:roles)
        XCTAssertFalse(prompt.contains("ancestor"))
        for s in seeds { XCTAssertTrue(prompt.contains(s.canonicalName)) }
    }
    func testRetryRotatesCallbackToken() throws {
        var c=GenerationCoordinator(); let old=UUID()
        c.prepare(id:old); _ = c.present(old); c.cancel(old); c.didDismiss(old)
        let fresh=try XCTUnwrap(c.sessionID)
        XCTAssertNotEqual(fresh,old)
        XCTAssertTrue(c.present(fresh)); XCTAssertFalse(c.accept(old)); XCTAssertTrue(c.accept(fresh))
    }
    func testSemanticNearFarAndCategoryShift() throws {
        let cat=try EmojiCatalog.bundled(), engine=TripletSearchEngine(catalog:cat)
        let parent=try ["butterfly","owl","octopus"].map { name in try XCTUnwrap(cat.concepts.first { $0.canonicalName==name }).id }
        var settings=EvolutionSettings(); settings.regime = .wild; settings.mutationCount=3; settings.excludedTags=[]
        var near=0.0, far=0.0, rng=SplitMix64(seed:1000)
        let sim=LocalSimilarity(concepts:cat.concepts)
        for strategy in [MutationStrategy.semanticNear,.semanticFar] {
            settings.mutation=strategy
            for _ in 0..<16 {
                let child=try engine.select(settings:settings,parent:parent,rng:&rng)
                let value=zip(child.conceptIDs,parent).map { sim.similarity(cat.concepts[$0],cat.concepts[$1]) }.reduce(0,+)
                if strategy == .semanticNear { near += value } else { far += value }
            }
        }
        XCTAssertGreaterThan(near,far)
        settings.mutation = .categoryShift
        let child=try engine.select(settings:settings,parent:parent,rng:&rng)
        for i in 0..<3 { XCTAssertNotEqual(cat.concepts[child.conceptIDs[i]].subgroup,cat.concepts[parent[i]].subgroup) }
    }
    func testRegimesAndHardExclusions() throws {
        let cat=try EmojiCatalog.bundled(), scorer=TripletScorer()
        let arrows=Array(cat.concepts.filter { $0.subgroup=="arrow" }.prefix(3))
        var settings=EvolutionSettings()
        XCTAssertFalse(try scorer.evaluate(arrows,settings:settings).accepted)
        settings.regime = .wild
        XCTAssertTrue(try scorer.evaluate(arrows,settings:settings).accepted)
        settings.allowedGroups=["Animals & Nature"]
        XCTAssertTrue(try scorer.evaluate(arrows,settings:settings).reasons.contains(.excludedConcept))
        var rng=SplitMix64(seed:765), history=SearchHistory()
        history.recentGenerations=[[0,1,2,3,4,5,6,7,8,9]]
        let candidate=try TripletSearchEngine(catalog:cat).select(settings:settings,history:history,rng:&rng)
        XCTAssertTrue(candidate.conceptIDs.allSatisfy { cat.concepts[$0].group=="Animals & Nature" && $0>9 })
    }
}
