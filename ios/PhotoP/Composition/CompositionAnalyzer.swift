@preconcurrency import Vision
@preconcurrency import CoreVideo
import ImageIO
import Foundation

// AVFoundation's frame is retained for the request. Both Vision and Metal only
// read it; no application code mutates its planes or attachments after delivery.
private struct ImmutableVisionFrame: @unchecked Sendable { let buffer: CVPixelBuffer }

// One on-device Vision request in flight, at most 2 Hz. Independent from GPU
// readiness events, so an AI update cannot hide a valid preview frame.
final class CompositionAnalyzer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.photop.composition", qos: .utility)
    private let lock = NSLock()
    private var scene: GuideScene = .general
    private var enabled = false
    private var running = false
    private var busy = false
    private var generation: UInt64 = 0
    private var lastTime = -Double.infinity
    private var currentID: UUID?
    private let completion: @Sendable (CompositionSnapshot) -> Void
    init(completion: @escaping @Sendable (CompositionSnapshot) -> Void) { self.completion = completion }
    func configure(enabled: Bool, scene: GuideScene) {
        lock.withLock { self.enabled = enabled; self.scene = scene; generation &+= 1; currentID = nil }
    }
    func setRunning(_ value: Bool) { lock.withLock { running = value; generation &+= 1; currentID = nil } }
    func isCurrent(_ snapshot: CompositionSnapshot) -> Bool { lock.withLock { currentID == snapshot.id && enabled && running } }
    func offer(_ buffer: CVPixelBuffer) {
        let request: (GuideScene, UInt64, Double)? = lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            guard enabled, running, !busy, now - lastTime >= 0.5 else { return nil }
            busy = true; lastTime = now
            return (scene, generation, now)
        }
        guard let (scene, generation, time) = request else { return }
        let frame = ImmutableVisionFrame(buffer: buffer)
        queue.async { [self, frame] in
            let snapshot = Self.analyze(frame.buffer, scene: scene, time: time)
            let accepted = lock.withLock { () -> Bool in
                busy = false
                guard self.generation == generation, enabled, running else { return false }
                currentID = snapshot.id; return true
            }
            if accepted { completion(snapshot) }
        }
    }
    private static func analyze(_ buffer: CVPixelBuffer, scene: GuideScene, time: Double) -> CompositionSnapshot {
        var bodies: [[String: CGPoint]] = [], polygons: [[CGPoint]] = [], advice = "검출 결과가 없습니다."
        do {
            // The capture connection already rotates/mirrors these pixels.
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
            switch scene {
            case .portrait:
                let request = VNDetectHumanBodyPoseRequest(); try handler.perform([request])
                let joints: [(String, VNHumanBodyPoseObservation.JointName)] = [("nose", .nose), ("neck", .neck),
                    ("ls", .leftShoulder), ("rs", .rightShoulder), ("le", .leftElbow), ("re", .rightElbow),
                    ("lw", .leftWrist), ("rw", .rightWrist), ("lh", .leftHip), ("rh", .rightHip),
                    ("lk", .leftKnee), ("rk", .rightKnee), ("la", .leftAnkle), ("ra", .rightAnkle)]
                for observation in (request.results ?? []).prefix(4) where observation.confidence >= 0.5 {
                    let recognized = try observation.recognizedPoints(.all)
                    let pairs = joints.compactMap { name, key -> (String, CGPoint)? in
                        guard let p = recognized[key], p.confidence >= 0.4 else { return nil }
                        return (name, p.location)
                    }
                    if pairs.count >= 3 { bodies.append(Dictionary(uniqueKeysWithValues: pairs)) }
                }
                advice = GuideGeometry.portraitAdvice(bodies)
            case .architecture:
                let request = VNDetectRectanglesRequest(); request.maximumObservations = 4; request.minimumConfidence = 0.6
                try handler.perform([request])
                polygons = (request.results ?? []).map { [$0.topLeft, $0.topRight, $0.bottomRight, $0.bottomLeft] }
                advice = polygons.isEmpty ? "직사각형 가장자리를 찾지 못했습니다." : "검출된 가장자리와 수직 기준선을 비교해 보세요. 건물 판별은 아닙니다."
            case .landscape:
                let request = VNDetectHorizonRequest(); try handler.perform([request])
                if let horizon = request.results?.first, horizon.confidence >= 0.5 {
                    advice = String(format: "추정 수평선 각도 %.1f° · 하늘/전경 비율을 확인해 보세요.", Double(horizon.angle) * 180 / .pi)
                }
            case .general:
                let request = VNGenerateAttentionBasedSaliencyImageRequest(); try handler.perform([request])
                polygons = (request.results?.first?.salientObjects ?? []).filter { $0.confidence >= 0.5 }.prefix(4).map {
                    let b = $0.boundingBox
                    return [.init(x: b.minX, y: b.minY), .init(x: b.maxX, y: b.minY), .init(x: b.maxX, y: b.maxY), .init(x: b.minX, y: b.maxY)]
                }
                if !polygons.isEmpty { advice = "관심 영역과 주변 여백의 균형을 확인해 보세요." }
            }
        } catch { advice = "현재 프레임의 온디바이스 분석을 수행하지 못했습니다." }
        return CompositionSnapshot(generatedAt: time, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                                   bodies: bodies, polygons: polygons, advice: advice)
    }
}
