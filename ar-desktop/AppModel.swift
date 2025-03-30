import SwiftUI

@MainActor
class AppModel: ObservableObject {
    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    @Published var immersiveSpaceState = ImmersiveSpaceState.closed

    // ✅ Add this struct if it's not already there
    struct FilePreviewInfo: Equatable {
        var label: String
        var fileType: String
        var fileLocation: String
    }

    @Published var previewedFile: FilePreviewInfo? = nil

    // ✅ Add this property to track window state
    @Published var isPreviewWindowOpen: Bool = false
}
