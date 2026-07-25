import Foundation

public enum MediaInformationField: String, Hashable, Sendable {
    case fileName
    case date
    case mediaType
    case fileSize
    case directory
    case source
}

public struct MediaInformationRow: Identifiable, Equatable, Sendable {
    public let id: MediaInformationField
    public let title: String
    public let value: String

    public init(id: MediaInformationField, title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

public struct MediaInformationPresentation: Equatable, Sendable {
    public let compactDateText: String
    public let rows: [MediaInformationRow]

    public init(
        item: MediaItem,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: "zh_CN")
    ) {
        let date = Self.datePresentation(for: item, timeZone: timeZone, locale: locale)
        compactDateText = date.compactText

        var availableRows = [
            MediaInformationRow(id: .fileName, title: "文件名", value: item.name),
            MediaInformationRow(id: .date, title: date.title, value: date.value),
            MediaInformationRow(
                id: .mediaType,
                title: "类型",
                value: item.kind == .photo ? "照片" : "视频"
            ),
            MediaInformationRow(
                id: .fileSize,
                title: "文件大小",
                value: Self.fileSizeText(item.size)
            )
        ]
        if item.sourceID == .familyMedia {
            availableRows.append(
                MediaInformationRow(
                    id: .directory,
                    title: "所在文件夹",
                    value: Self.directoryText(item.mediaPath)
                )
            )
        }
        availableRows.append(
            MediaInformationRow(
                id: .source,
                title: "来源",
                value: Self.sourceText(item.sourceID)
            )
        )
        rows = availableRows
    }

    private static func datePresentation(
        for item: MediaItem,
        timeZone: TimeZone,
        locale: Locale
    ) -> (title: String, value: String, compactText: String) {
        let title: String
        let prefix: String?
        let date: Date?
        switch item.sourceID {
        case .jellyfin:
            title = "加入时间"
            prefix = title
            date = meaningfulDate(item.modified)
        case .familyMedia:
            if let capturedAt = meaningfulDate(item.capturedAt) {
                title = "拍摄时间"
                prefix = nil
                date = capturedAt
            } else {
                title = "文件日期"
                prefix = title
                date = meaningfulDate(item.modified)
            }
        }

        guard let date else {
            return (title, "未知", "时间未知")
        }
        let formatted = format(date: date, timeZone: timeZone, locale: locale)
        let compact = prefix.map { "\($0) · \(formatted)" } ?? formatted
        return (title, formatted, compact)
    }

    private static func meaningfulDate(_ date: Date?) -> Date? {
        guard let date, date != .distantPast, date != .distantFuture else { return nil }
        return date
    }

    private static func format(date: Date, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func fileSizeText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "未知" }
        let units: [(name: String, bytes: Double)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1_024)
        ]
        guard let unit = units.first(where: { Double(bytes) >= $0.bytes }) else {
            return "\(bytes) B"
        }
        let value = Double(bytes) / unit.bytes
        let number = value >= 10 || value.rounded() == value
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(number) \(unit.name)"
    }

    private static func directoryText(_ mediaPath: String) -> String {
        let directory = (mediaPath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? "未分类" : directory
    }

    private static func sourceText(_ sourceID: MediaSourceID) -> String {
        switch sourceID {
        case .familyMedia: "家庭媒体"
        case .jellyfin: "Jellyfin"
        }
    }
}
