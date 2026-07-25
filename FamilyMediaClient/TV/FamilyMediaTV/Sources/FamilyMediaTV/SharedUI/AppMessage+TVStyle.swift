import FamilyMediaCore
import SwiftUI

extension AppMessage {
    var tvForegroundStyle: Color {
        switch style {
        case .info, .success:
            return .white
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
