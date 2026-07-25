import FamilyMediaCore
import SwiftUI

extension View {
    func reportPhotoLoadState(
        _ state: MediaPhotoLoadState,
        itemID: String,
        to handler: @escaping (String, MediaPhotoLoadState) -> Void
    ) -> some View {
        modifier(
            PhotoLoadStateReportingModifier(
                state: state,
                itemID: itemID,
                handler: handler
            )
        )
    }
}

private struct PhotoLoadStateReportingModifier: ViewModifier {
    let state: MediaPhotoLoadState
    let itemID: String
    let handler: (String, MediaPhotoLoadState) -> Void

    private var observation: Observation {
        Observation(itemID: itemID, state: state)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                handler(itemID, state)
            }
            .onChange(of: observation) { _, newValue in
                handler(newValue.itemID, newValue.state)
            }
    }
}

private struct Observation: Equatable {
    let itemID: String
    let state: MediaPhotoLoadState
}
