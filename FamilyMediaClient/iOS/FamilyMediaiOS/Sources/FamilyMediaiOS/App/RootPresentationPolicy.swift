import UIKit

enum RootPresentationMode: Equatable {
    case phoneTabs
    case iPadSplit
}

enum RootPresentationPolicy {
    static func mode(for userInterfaceIdiom: UIUserInterfaceIdiom) -> RootPresentationMode {
        userInterfaceIdiom == .pad ? .iPadSplit : .phoneTabs
    }
}
