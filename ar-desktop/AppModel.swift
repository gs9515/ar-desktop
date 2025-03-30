import SwiftUI

/// Maintains app-wide state
@MainActor
class AppModel: ObservableObject {
    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    @Published var immersiveSpaceState = ImmersiveSpaceState.closed

    struct FilePreviewInfo: Equatable {
        var label: String
        var fileType: String
        var fileLocation: String
    }

    @Published var previewedFile: FilePreviewInfo? = nil
}
