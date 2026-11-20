// Compile together with HighResolutionPolicy, SoftwareDepthPolicy and
// DepthProcessingCore FROM THE REVISION being measured. Not real-photo evidence.
import Foundation

@main struct DepthSyntheticBaseline {
    static func main() throws {
        let w = 17, h = 17, f = SIMD3<Float>(0.9,0.15,0.1), b = SIMD3<Float>(0.05,0.4,0.6)
        let truth: [Float] = (0..<(w*h)).map { i in min(1,max(0,Float(i % w - 6)/4)) }
        let prior = truth.map { $0 > 0 && $0 < 1 ? $0 * 0.6+0.1 : $0 }
        let color = truth.map { f * $0 + b * (1-$0) }
        guard let surface = DepthMatteCore.refine(alpha: prior,color: color,width: w,height: h) else { throw CocoaError(.coderInvalidValue) }
        let unknown = truth.indices.filter { truth[$0] > 0 && truth[$0] < 1 }
        let seeds = truth.indices.filter { truth[$0] == 0 || truth[$0] == 1 }
        let error = unknown.reduce(Float(0)) { $0+abs(surface.alpha[$1]-truth[$1]) }/Float(unknown.count)
        let seedError = seeds.reduce(Float(0)) { $0+abs(surface.alpha[$1]-truth[$1]) }/Float(seeds.count)
        let thinTruth: [Float] = (0..<(w*h)).map { i in
            if i / w % 6 == 3 { return 0 } // gaps must remain background
            return i % w == 8 ? 1 : (i % w == 7 || i % w == 9 ? 0.35 : 0)
        }
        let thinPrior = thinTruth.map { $0 > 0 && $0 < 1 ? Float(0.2) : $0 }
        let thinColor = thinTruth.map { f * $0 + b * (1-$0) }
        guard let thin = DepthMatteCore.refine(alpha: thinPrior,color: thinColor,width: w,height: h) else { throw CocoaError(.coderInvalidValue) }
        let thinEdge = thinTruth.indices.filter { thinTruth[$0] > 0 && thinTruth[$0] < 1 }
        let thinSeeds = thinTruth.indices.filter { thinTruth[$0] == 0 || thinTruth[$0] == 1 }
        let thinReport: [String: Any] = ["kind": "one-pixel-strand-with-fractional-edges-and-background-gaps",
            "boundaryMAE": thinEdge.reduce(Float(0)) { $0+abs(thin.alpha[$1]-thinTruth[$1]) }/Float(thinEdge.count),
            "hardSeedMAE": thinSeeds.reduce(Float(0)) { $0+abs(thin.alpha[$1]-thinTruth[$1]) }/Float(thinSeeds.count)]
        let report: [String: Any] = ["thinStructure": thinReport, "kind": "synthetic-color-line-ground-truth", "source": CommandLine.arguments.dropFirst().first ?? "unspecified",
            "width": w,"height": h,"boundaryMAE": error,"hardSeedMAE": seedError,"alphaMiddleRow": Array(surface.alpha[(8*w)..<(9*w)]),
            "realCaptureCount": 0,"deviceBenchmark": false]
        let data = try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys])
        print(String(decoding: data,as: UTF8.self))
    }
}
