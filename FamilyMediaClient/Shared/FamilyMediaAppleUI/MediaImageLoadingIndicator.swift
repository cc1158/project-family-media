import SwiftUI

struct MediaImageLoadingIndicator: View {
    let progress: Double?

    var body: some View {
        Group {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .accessibilityValue("\(Int(progress * 100))%")
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .tint(.white)
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        .accessibilityLabel("正在加载高清图片")
        .allowsHitTesting(false)
    }
}
