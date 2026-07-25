import FamilyMediaCore

extension MediaInformationField {
    var systemImage: String {
        switch self {
        case .fileName: "doc"
        case .date: "calendar"
        case .mediaType: "photo.on.rectangle"
        case .fileSize: "internaldrive"
        case .directory: "folder"
        case .source: "server.rack"
        }
    }
}
