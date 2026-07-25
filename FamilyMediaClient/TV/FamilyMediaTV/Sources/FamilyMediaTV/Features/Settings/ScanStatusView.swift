import FamilyMediaCore
import SwiftUI

struct ScanStatusView: View {
    let scanStatus: ScanStatus

    private var presentation: ScanStatusPresentation {
        ScanStatusPresentation(scanStatus: scanStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("扫描结果")
                .font(.title3.bold())
            Text("状态：\(presentation.status)")

            ForEach(presentation.rows, id: \.title) { row in
                Text("\(row.title)：\(row.value)")
            }

            if let error = presentation.error {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .font(.body)
    }
}
