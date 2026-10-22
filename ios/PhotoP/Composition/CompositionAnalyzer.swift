@preconcurrency import Vision
@preconcurrency import CoreVideo
import ImageIO
import Foundation
import CoreImage

// AVFoundation's frame is retained for the request. Both Vision and Metal only
// read it; no application code mutates its planes or attachments after delivery.
private struct ImmutableVisionFrame: @unchecked Sendable { let buffer: CVPixelBuffer }

// One on-device Vision batch in flight, at most 5 Hz. Independent from GPU
// readiness events, so an AI update cannot hide a valid preview frame.
final class CompositionAnalyzer: @unchecked Sendable {
    // Live/review clients share one inference gate, including a live batch that
    // was already running when the UI paused it for post-capture review.
    private static let inferenceLock = NSLock()
    private let queue = DispatchQueue(label: "com.photop.composition", qos: .utility)
    private let lock = NSLock()
    private var scene: GuideScene = .general
    private var enabled = false
    private var running = false
    private var busy = false
    private var generation: UInt64 = 0
    private var lastTime = -Double.infinity
    private var currentID: UUID?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var cachedEvidence = SceneEvidence()
    private var cachedEpoch: UInt64?
    private var lastDetailedTime = -Double.infinity
    private let completion: @Sendable (CompositionSnapshot) -> Void
    init(completion: @escaping @Sendable (CompositionSnapshot) -> Void) { self.completion = completion }
    func configure(enabled: Bool, scene: GuideScene) {
        lock.withLock {
            guard self.enabled != enabled || self.scene != scene else { return }
            self.enabled = enabled; self.scene = scene; generation &+= 1; currentID = nil; lastTime = -.infinity
        }
    }
    func setRunning(_ value: Bool) { lock.withLock { running = value; generation &+= 1; currentID = nil; lastTime = -.infinity } }
    func invalidate() { lock.withLock { generation &+= 1; currentID = nil; lastTime = -.infinity } }
    func isCurrent(_ snapshot: CompositionSnapshot) -> Bool { lock.withLock { currentID == snapshot.id && enabled && running } }
    func offer(_ buffer: CVPixelBuffer, minimumInterval: Double = 0.2) {
        let request: (GuideScene, UInt64, Double)? = lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            guard enabled, running, !busy, minimumInterval.isFinite, minimumInterval >= 0.2, now - lastTime >= minimumInterval else { return nil }
            busy = true; lastTime = now
            return (scene, generation, now)
        }
        guard let (scene, generation, time) = request else { return }
        let frame = ImmutableVisionFrame(buffer: buffer)
        queue.async { [self, frame] in
            let snapshot = autoreleasepool { analyze(frame.buffer, scene: scene, time: time, epoch: generation) }
            let accepted = lock.withLock { () -> Bool in
                busy = false
                guard self.generation == generation, enabled, running,
                      ProcessInfo.processInfo.systemUptime - time <= 0.65 else { return false }
                currentID = snapshot.id; return true
            }
            if accepted { completion(snapshot) }
        }
    }
    private func analyze(_ buffer: CVPixelBuffer, scene: GuideScene, time: Double, epoch: UInt64) -> CompositionSnapshot {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let image = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 640 / max(image.extent.width, image.extent.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(small, from: small.extent) else {
            return CompositionSnapshot(generatedAt: time, width: width, height: height, bodies: [], polygons: [], advice: "분석 이미지 준비 실패", epoch: epoch, detectionAvailable: false)
        }
        let detailed = cachedEpoch != epoch || time - lastDetailedTime >= 0.8
        var snapshot = Self.analyzeImage(cg, width: width, height: height, scene: scene, time: time, epoch: epoch, detailed: detailed)
        if detailed {
            cachedEpoch = epoch; lastDetailedTime = time; cachedEvidence = snapshot.evidence
        } else if cachedEvidence.isFresh(at: time) {
            let photo = snapshot.evidence.photometry
            snapshot.evidence = cachedEvidence; snapshot.evidence.photometry = photo
        }
        return snapshot
    }

    // Shared by live capture and post-capture review. Caller provides already
    // oriented pixels and bounds resolution; never executed on the main thread.
    static func analyzeImage(_ cg: CGImage, width: Int, height: Int, scene: GuideScene, time: Double,
                             epoch: UInt64 = 0, detailed: Bool = true) -> CompositionSnapshot {
        inferenceLock.lock(); defer { inferenceLock.unlock() }
        if Task.isCancelled {
            return CompositionSnapshot(generatedAt: time, width: width, height: height, bodies: [], polygons: [],
                advice: "분석 취소", epoch: epoch, detectionAvailable: false)
        }
        var bodies: [[String: CGPoint]] = [], polygons: [[CGPoint]] = [], advice = "검출 결과가 없습니다."
        var people: [DetectedPerson] = []
        var peopleMessage = "인물을 찾지 못했습니다. 인물이 보이도록 프레임을 조절하세요."
        var evidence = SceneEvidence(generatedAt: time)
        var detectionAvailable = true
        evidence.photometry = SceneImageRaster.photometry(cg)
        if detailed { evidence.lines = evidence.photometry?.lines() ?? [] }
        do {
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            let humanRequest = VNDetectHumanRectanglesRequest()
            humanRequest.upperBodyOnly = false
            let faceRequest = VNDetectFaceRectanglesRequest()
            try handler.perform([humanRequest, faceRequest])
            // Face CENTER is measured, not inferred eye position or gaze.
            func topLeft(_ rect: CGRect) -> CGRect {
                CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
            }
            let humans = (humanRequest.results ?? []).filter { $0.confidence >= 0.5 }.prefix(12)
            let faces = Array((faceRequest.results ?? []).filter { $0.confidence >= 0.6 }.prefix(12))
            var assignedFaces = Set<Int>()
            for human in humans {
                let box = topLeft(human.boundingBox)
                let faceIndex = faces.indices.filter { index in
                    let face = topLeft(faces[index].boundingBox)
                    return !assignedFaces.contains(index) && box.contains(CGPoint(x: face.midX, y: face.midY))
                }.min { faces[$0].boundingBox.midY > faces[$1].boundingBox.midY }
                let center = faceIndex.map { index -> CGPoint in
                    assignedFaces.insert(index)
                    let face = topLeft(faces[index].boundingBox)
                    return CGPoint(x: face.midX, y: face.midY)
                }
                people.append(DetectedPerson(bounds: box, faceCenter: center, confidence: human.confidence))
            }
            // Close-up faces can be valid even when a human rectangle is absent.
            for index in faces.indices where !assignedFaces.contains(index) {
                let box = topLeft(faces[index].boundingBox)
                // A second face inside an existing human is ambiguous, not a
                // second person proven by this detector. Avoid double counting.
                guard !people.contains(where: { $0.bounds.contains(CGPoint(x: box.midX, y: box.midY)) }) else { continue }
                people.append(DetectedPerson(bounds: box, faceCenter: CGPoint(x: box.midX, y: box.midY),
                                             confidence: faces[index].confidence, kind: .face))
            }
            if detailed {
                // Independent optional requests: lack of a horizon/rectangle is
                // not a person-analysis failure or an object classification.
                let horizon = VNDetectHorizonRequest()
                if (try? handler.perform([horizon])) != nil, let value = horizon.results?.first, value.confidence >= 0.5 {
                    // Vision uses an upward Y axis; all evidence uses top-left.
                    evidence.horizonDegrees = -Double(value.angle) * 180 / .pi
                }
                let rectangles = VNDetectRectanglesRequest(); rectangles.maximumObservations = 6; rectangles.minimumConfidence = 0.6
                if (try? handler.perform([rectangles])) != nil {
                    evidence.rectangles = (rectangles.results ?? []).map { quad in
                        [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
                    }
                }
                let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
                if (try? handler.perform([saliency])) != nil {
                    evidence.saliency = (saliency.results?.first?.salientObjects ?? []).filter { $0.confidence >= 0.5 }.prefix(6).map { topLeft($0.boundingBox) }
                }
            }
            do {
                switch scene {
                case .portrait:
                    guard detailed else { break }
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
                    polygons = evidence.rectangles.map { $0.map { CGPoint(x: $0.x, y: 1 - $0.y) } }
                    advice = polygons.isEmpty ? "직사각형 가장자리를 찾지 못했습니다." : "검출된 가장자리와 수직 기준선을 비교해 보세요. 건물 판별은 아닙니다."
                case .landscape:
                    if let angle = evidence.horizonDegrees {
                        advice = String(format: "추정 수평선 각도 %.1f° · 위치가 아닌 방향입니다.", angle)
                    }
                case .general:
                    polygons = evidence.saliency.map {
                        let b = CGRect(x: $0.minX, y: 1 - $0.maxY, width: $0.width, height: $0.height)
                        return [.init(x: b.minX, y: b.minY), .init(x: b.maxX, y: b.minY), .init(x: b.maxX, y: b.maxY), .init(x: b.minX, y: b.maxY)]
                    }
                    if !polygons.isEmpty { advice = "관심 영역과 주변 여백의 균형을 확인해 보세요." }
                }
            } catch {
                // Optional saliency/pose/geometry failure must not discard a
                // successful person detection batch.
                advice = "장면 보조 분석을 수행하지 못했습니다. 인물 가이드는 유지합니다."
            }
        } catch {
            detectionAvailable = false
            advice = "현재 프레임의 온디바이스 분석을 수행하지 못했습니다."
            people = []; peopleMessage = "인물 분석을 수행하지 못했습니다. 촬영과 수동 구도선은 계속 사용할 수 있습니다."
        }
        return CompositionSnapshot(generatedAt: time, width: width, height: height,
                                   bodies: bodies, polygons: polygons, advice: advice, epoch: epoch, people: people,
                                   evidence: evidence, peopleAnalysisMessage: peopleMessage, detectionAvailable: detectionAvailable)
    }
}
