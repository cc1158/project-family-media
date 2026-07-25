import FamilyMediaCore
import SwiftUI

extension AppMessage {
    var foregroundStyle: Color {
        switch style {
        case .info, .success:
            return .primary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var overlayForegroundStyle: Color {
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
