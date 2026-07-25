import SwiftUI

struct NumericSettingRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack(spacing: 24) {
            Text(title)
                .frame(width: 220, alignment: .leading)

            Button {
                value = max(range.lowerBound, value - 1)
            } label: {
                Image(systemName: "minus")
            }
            .disabled(value <= range.lowerBound)

            Text("\(value) \(unit)")
                .font(.title3.monospacedDigit())
                .frame(width: 120)

            Button {
                value = min(range.upperBound, value + 1)
            } label: {
                Image(systemName: "plus")
            }
            .disabled(value >= range.upperBound)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}
