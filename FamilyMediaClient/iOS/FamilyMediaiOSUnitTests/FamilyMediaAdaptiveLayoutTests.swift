import SwiftUI
import UIKit
import XCTest
@testable import FamilyMediaiOS

final class FamilyMediaAdaptiveLayoutTests: XCTestCase {
    func testRootPresentationDependsOnDeviceCategory() {
        XCTAssertEqual(
            RootPresentationPolicy.mode(for: .phone),
            .phoneTabs
        )
        XCTAssertEqual(
            RootPresentationPolicy.mode(for: .pad),
            .iPadSplit
        )
    }

    func testCategoryLayoutUsesContentWidthBoundaries() {
        XCTAssertEqual(
            categoryLayout(width: 519),
            .singleColumn
        )
        XCTAssertEqual(
            categoryLayout(width: 520),
            .featured
        )
        XCTAssertEqual(
            categoryLayout(width: 779),
            .featured
        )
        XCTAssertEqual(
            categoryLayout(width: 780),
            .threeColumns
        )
    }

    func testCompactWidthAndAccessibilityTextAlwaysUseSingleColumn() {
        XCTAssertEqual(
            categoryLayout(
                width: 1_000,
                sizeClass: .compact
            ),
            .singleColumn
        )
        XCTAssertEqual(
            categoryLayout(
                width: 1_000,
                dynamicTypeSize: .accessibility1
            ),
            .singleColumn
        )
    }

    func testIPadSidebarUsesReadableWidthRange() {
        XCTAssertEqual(IPadSidebarMetrics.minimumWidth, 240)
        XCTAssertEqual(IPadSidebarMetrics.idealWidth, 260)
        XCTAssertEqual(IPadSidebarMetrics.maximumWidth, 300)
        XCTAssertLessThan(
            IPadSidebarMetrics.minimumWidth,
            IPadSidebarMetrics.idealWidth
        )
        XCTAssertLessThan(
            IPadSidebarMetrics.idealWidth,
            IPadSidebarMetrics.maximumWidth
        )
    }

    func testMediaGridMetricsRemainConsistentAcrossContentStates() {
        let compactColumns = FamilyMediaAdaptiveLayout.mediaColumns(
            for: .compact,
            dynamicTypeSize: .large
        )
        let accessibleColumns = FamilyMediaAdaptiveLayout.mediaColumns(
            for: .compact,
            dynamicTypeSize: .accessibility1
        )
        let regularColumns = FamilyMediaAdaptiveLayout.mediaColumns(
            for: .regular,
            dynamicTypeSize: .large
        )

        XCTAssertEqual(compactColumns.count, 2)
        XCTAssertEqual(accessibleColumns.count, 1)
        XCTAssertEqual(regularColumns.count, 1, "常规宽度使用单个 adaptive GridItem")
        XCTAssertEqual(
            FamilyMediaAdaptiveLayout.mediaGridHorizontalPadding(for: .compact),
            16
        )
        XCTAssertEqual(
            FamilyMediaAdaptiveLayout.mediaGridHorizontalPadding(for: .regular),
            24
        )
    }

    private func categoryLayout(
        width: CGFloat,
        sizeClass: UserInterfaceSizeClass? = .regular,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> MediaCategoryLayout {
        MediaContentLayoutPolicy.categoryLayout(
            availableWidth: width,
            horizontalSizeClass: sizeClass,
            dynamicTypeSize: dynamicTypeSize
        )
    }
}
