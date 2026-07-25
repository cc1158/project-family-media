import FamilyMediaCore

extension MediaSourceContext {
    func containerTypeLabel(containerID: String?) -> String {
        guard containerID == nil else { return "文件夹" }
        switch catalogStructure {
        case .folderTree:
            return "文件夹"
        case .libraryRoot:
            return "媒体库"
        }
    }
}
