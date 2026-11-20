import SwiftUI

@main
struct PhotoPApp: App {
    var body: some Scene { WindowGroup { root } }
    @ViewBuilder private var root: some View {
        #if DEBUG && targetEnvironment(simulator)
        // Test actual editors directly; an onAppear cover can be dropped while
        // the first window is attaching. Device/release routing is unchanged.
        if ProcessInfo.processInfo.arguments.contains("--ui-review"), ProcessInfo.processInfo.arguments.contains("--review-depth-editor") {
            DepthEditorReviewFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-review"), ProcessInfo.processInfo.arguments.contains("--review-video-depth-editor") {
            VideoDepthReviewFixture()
        } else { CameraView() }
        #else
        CameraView()
        #endif
    }
}
