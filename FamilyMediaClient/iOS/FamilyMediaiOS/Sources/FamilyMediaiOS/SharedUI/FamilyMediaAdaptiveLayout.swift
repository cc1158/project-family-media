import SwiftUI

enum FamilyMediaAdaptiveLayout {
    static let compactContentMaxWidth: CGFloat = 760
    static let wideContentMaxWidth: CGFloat = 980
    static let settingsWideContentMaxWidth: CGFloat = 1_040

    static func overviewColumnCount(
        for horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Int {
        horizontalSizeClass == .regular ? 2 : 1
    }

    static func overviewColumns(
        for horizontalSizeClass: UserInterfaceSizeClass?,
        spacing: CGFloat
    ) -> [GridItem] {
        flexibleColumns(
            count: overviewColumnCount(for: horizontalSizeClass),
            spacing: spacing
        )
    }

    static func mediaColumns(
        for horizontalSizeClass: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize
    ) -> [GridItem] {
        if horizontalSizeClass == .regular {
            return [
                GridItem(
                    .adaptive(
                        minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 170,
                        maximum: dynamicTypeSize.isAccessibilitySize ? 360 : 260
                    ),
                    spacing: 13,
                    alignment: .top
                )
            ]
        }

        return flexibleColumns(
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
            spacing: 13
        )
    }

    static func mediaGridHorizontalPadding(
        for horizontalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    private static func flexibleColumns(count: Int, spacing: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
            count: count
        )
    }
}

enum MediaCategoryLayout: Equatable {
    case singleColumn
    case featured
    case threeColumns
}

enum MediaContentLayoutPolicy {
    static let horizontalPadding: CGFloat = 20
    static let spacing: CGFloat = 16
    static let cardMinimumHeight: CGFloat = 112
    static let featuredMinimumWidth: CGFloat = 520
    static let threeColumnMinimumWidth: CGFloat = 780

    static func categoryLayout(
        availableWidth: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize
    ) -> MediaCategoryLayout {
        guard
            horizontalSizeClass == .regular,
            !dynamicTypeSize.isAccessibilitySize
        else {
            return .singleColumn
        }

        if availableWidth >= threeColumnMinimumWidth {
            return .threeColumns
        }
        if availableWidth >= featuredMinimumWidth {
            return .featured
        }
        return .singleColumn
    }
}
