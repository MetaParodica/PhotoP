// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Portable tests of the SAME geometry/tracking code shipped by the iOS target.
// This is not an iOS build and cannot exercise Vision, AVFoundation or SwiftUI.
let testPath = "ios/PhotoPTests"
let testURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(testPath)
let coreTests = ["CompositionTrackingTests.swift", "CaptureWorkflowTests.swift", "IntelligentCoachTests.swift", "PhotoReviewCoreTests.swift", "HighResolutionPolicyTests.swift", "LookEffectAssessmentTests.swift"]
let excludedTests = try FileManager.default.contentsOfDirectory(atPath: testURL.path)
    .filter { !coreTests.contains($0) }
let cameraPath = "ios/PhotoP/Camera"
let cameraURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(cameraPath)
let excludedCameraSources = try FileManager.default.contentsOfDirectory(atPath: cameraURL.path)
    .filter { $0 != "CaptureWorkflowPolicy.swift" }
let coreSources = ["CompositionGuide.swift", "CompositionTracking.swift", "SceneMeasurements.swift", "IntelligentComposition.swift", "CameraCoach.swift", "PhotoReview.swift"]
let coreURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ios/PhotoP/Composition")
let excludedCoreSources = try FileManager.default.contentsOfDirectory(atPath: coreURL.path).filter { !coreSources.contains($0) }
let imagePath = "ios/PhotoP/Processing"
let imageURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(imagePath)
let imageSources = ["HighResolutionPolicy.swift", "CubeLUT.swift", "LookEffectAssessment.swift"]
let excludedImageSources = try FileManager.default.contentsOfDirectory(atPath: imageURL.path).filter { !imageSources.contains($0) }

let package = Package(
    name: "PhotoPCompositionCore",
    products: [.library(name: "PhotoPCompositionCore", targets: ["PhotoPCompositionCore"])],
    targets: [
        .target(name: "PhotoPCompositionCore", path: "ios/PhotoP/Composition",
                exclude: excludedCoreSources, sources: coreSources,
                swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
        .target(name: "PhotoPCameraPolicies", path: cameraPath, exclude: excludedCameraSources,
                sources: ["CaptureWorkflowPolicy.swift"], swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
        .target(name: "PhotoPImagePolicies", path: imagePath, exclude: excludedImageSources, sources: imageSources,
                swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
        .testTarget(name: "PhotoPCompositionCoreTests", dependencies: ["PhotoPCompositionCore", "PhotoPCameraPolicies", "PhotoPImagePolicies"],
                    path: testPath, exclude: excludedTests, sources: coreTests)
    ]
)
