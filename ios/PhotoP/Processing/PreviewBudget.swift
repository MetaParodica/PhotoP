import Foundation

struct PreviewBudget: Equatable, Sendable {
    let maximumDimension: Int
    let framesPerSecond: Double
    let analysisInterval: Double
    let histogramInterval: Double
    // Preview/monitor budgets remain independent from person tracking cadence.
    var compositionInterval: Double {
        guard analysisInterval.isFinite else { return .infinity }
        return framesPerSecond >= 60 ? 0.2 : 0.4
    }
    init(thermal: ProcessInfo.ThermalState, lowPower: Bool) {
        switch thermal {
        case .critical: maximumDimension = 480; framesPerSecond = 10; analysisInterval = .infinity; histogramInterval = 1
        case .serious: maximumDimension = 720; framesPerSecond = 20; analysisInterval = 1; histogramInterval = 0.5
        default: maximumDimension = lowPower ? 720 : 1024; framesPerSecond = lowPower ? 30 : 60; analysisInterval = lowPower ? 1 : 0.5; histogramInterval = lowPower ? 0.5 : 0.25
        }
    }
    func admits(time: Double, after previous: Double) -> Bool { time.isFinite && time >= previous && time - previous >= 1 / framesPerSecond }
}
