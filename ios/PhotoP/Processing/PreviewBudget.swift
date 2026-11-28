import Foundation

struct PreviewBudget: Equatable, Sendable {
    let maximumDimension: Int
    let framesPerSecond: Double
    let analysisInterval: Double
    let histogramInterval: Double
    let allowsDepthEffects: Bool
    // Preview/monitor budgets remain independent from person tracking cadence.
    let compositionInterval: Double
    init(thermal: ProcessInfo.ThermalState, lowPower: Bool, depthEnabled: Bool = false) {
        let dimension: Int, fps: Double, analysis: Double
        switch thermal {
        case .critical: dimension = 480; fps = 10; analysis = .infinity; histogramInterval = 1
        case .serious: dimension = 720; fps = 20; analysis = 1; histogramInterval = 0.5
        default: dimension = lowPower ? 720 : 1024; fps = lowPower ? 30 : 60; analysis = lowPower ? 1 : 0.5; histogramInterval = lowPower ? 0.5 : 0.25
        }
        compositionInterval = analysis.isFinite ? (fps >= 60 ? 0.2 : 0.4) : .infinity
        let depth = DepthPreviewWorkload(thermalLevel: thermal.rawValue, lowPower: lowPower)
        maximumDimension = depthEnabled ? min(dimension, depth.maximumDimension) : dimension
        framesPerSecond = depthEnabled ? min(fps, depth.framesPerSecond) : fps
        analysisInterval = depthEnabled ? depth.analysisInterval : analysis
        allowsDepthEffects = depth.allowsDepth
    }
    func admits(time: Double, after previous: Double) -> Bool { time.isFinite && time >= previous && time - previous >= 1 / framesPerSecond }
}
