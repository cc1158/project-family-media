import FamilyMediaCore
import SwiftUI

struct MediaInformationDetailView: View {
    let presentation: MediaInformationPresentation

    var body: some View {
        List(presentation.rows) { row in
            LabeledContent {
                Text(row.value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            } label: {
                Label(row.title, systemImage: row.id.systemImage)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("viewer.information.\(row.id.rawValue)")
        }
        .navigationTitle("媒体信息")
        .navigationBarTitleDisplayMode(.inline)
    }
}
