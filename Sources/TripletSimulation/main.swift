import Foundation
import GlyphCore

let args = CommandLine.arguments
let count = args.dropFirst().first.flatMap(Int.init) ?? 100_000
guard count > 0 else { throw SearchError.invalidSettings }
let catalog = try EmojiCatalog.bundled()
let scorer = TripletScorer(similarity:LocalSimilarity(concepts:catalog.concepts))
var settings = EvolutionSettings()
var rng = SplitMix64(seed:20260918)
let corpus = catalog.concepts.filter { $0.defaultEligibility == .strict && settings.excludedTags.isDisjoint(with:$0.exclusions) }
var histogram = [Int](repeating:0,count:10), rejections: [String:Int] = [:], roles: [String:Int] = [:], groups: [String:Int] = [:]
var accepted=0, duplicates=0, sum=0.0, meanSimilarity=0.0, seen: Set<TripletID> = []
struct Example: Codable { let names: [String]; let score: Double; let reasons: [String] }
var top: [Example]=[], bottom: [Example]=[], rejected: [Example]=[]
let start=Date()
for _ in 0..<count {
    var ids: [Int]=[]
    while ids.count<3 { let i=rng.index(count:corpus.count); if !ids.contains(i) { ids.append(i) } }
    let c=ids.map { corpus[$0] }
    let result=try scorer.evaluate(c,settings:settings)
    let id=try TripletID(conceptIDs:(c[0].id,c[1].id,c[2].id))
    if !seen.insert(id).inserted { duplicates += 1 }
    histogram[min(9,Int(result.score.total*10))] += 1
    sum += result.score.total; meanSimilarity += result.score.meanPairSimilarity
    let example=Example(names:c.map(\.canonicalName),score:result.score.total,reasons:result.reasons.map(\.rawValue))
    if result.accepted {
        accepted += 1; roles[result.score.bestRoleAssignment.template.rawValue,default:0] += 1
        for concept in c { groups[concept.group,default:0] += 1 }
        top.append(example); top.sort { $0.score > $1.score }; top=Array(top.prefix(5))
        bottom.append(example); bottom.sort { $0.score < $1.score }; bottom=Array(bottom.prefix(5))
    } else {
        for reason in result.reasons { rejections[reason.rawValue,default:0] += 1 }
        if rejected.count<10 { rejected.append(example) }
    }
}
let scoringSeconds=Date().timeIntervalSince(start)
var batchTimes:[Double]=[]
for _ in 0..<10 {
    let begin=Date()
    _ = try TripletSearchEngine(catalog:catalog).select(settings:settings,rng:&rng)
    batchTimes.append(Date().timeIntervalSince(begin))
}
struct Report: Codable {
    let catalogVersion, scoringVersion, proposalDistribution: String
    let count, accepted: Int
    let acceptanceRate, meanScore, meanPairSimilarity, duplicateRate, scoringSeconds: Double
    let scoreHistogram: [Int]
    let roleTemplateDistribution, unicodeGroupDistribution, rejectionReasons: [String:Int]
    let topScoring, bottomAccepted, hardRejected: [Example]
    let constructiveSelectionSeconds: [Double]
}
let report=Report(catalogVersion:catalog.version,scoringVersion:scorer.config.version,
    proposalDistribution:"Uniform distinct strict-corpus triples; independent of constructive selector",count:count,accepted:accepted,
    acceptanceRate:Double(accepted)/Double(count),meanScore:sum/Double(count),meanPairSimilarity:meanSimilarity/Double(count),
    duplicateRate:Double(duplicates)/Double(count),scoringSeconds:scoringSeconds,scoreHistogram:histogram,
    roleTemplateDistribution:roles,unicodeGroupDistribution:groups,rejectionReasons:rejections,
    topScoring:top,bottomAccepted:bottom,hardRejected:rejected,constructiveSelectionSeconds:batchTimes)
let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
let data=try encoder.encode(report)
if args.count>2 { try data.write(to:URL(fileURLWithPath:args[2]),options:.atomic) }
print(String(decoding:data,as:UTF8.self))
