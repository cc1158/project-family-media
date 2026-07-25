import XCTest

@MainActor
final class FamilyMediaiOSUITests: XCTestCase {
    func testFamilyMediaCardOpensDemoLibrary() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()

        XCTAssertTrue(
            app.staticTexts["海边的下午"].waitForExistence(timeout: 5),
            "家庭媒体入口应能进入演示媒体库"
        )
    }

    func testFamilyTimelineSwitchesBetweenMonthAndYear() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()

        XCTAssertTrue(element("media.browseMode", in: app).waitForExistence(timeout: 5))
        app.buttons["月份"].tap()
        XCTAssertTrue(app.staticTexts["2024年8月"].waitForExistence(timeout: 5))

        app.buttons["年份"].tap()
        XCTAssertTrue(element("media.timeline.year.2024", in: app).waitForExistence(timeout: 3))
    }

    func testReturningFromViewerKeepsCurrentMediaAvailable() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        let item = app.buttons["media.item.demo:familyMedia:family-1"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        let closeButton = app.buttons["viewer.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.tap()

        XCTAssertTrue(
            item.waitForExistence(timeout: 3),
            "退出查看器后应回到之前浏览的媒体位置"
        )
    }

    func testVideoViewerUsesScrubberAndThreeTransportButtons() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        let video = app.buttons["media.item.demo:familyMedia:family-2"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()

        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["上一个"].exists)
        XCTAssertTrue(app.buttons["播放"].exists || app.buttons["暂停"].exists)
        XCTAssertTrue(app.buttons["下一个"].exists)
        XCTAssertFalse(app.buttons["后退 10 秒"].exists)
        XCTAssertFalse(app.buttons["前进 10 秒"].exists)
    }

    func testNextItemKeepsTheSameViewerPresented() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        let firstItem = app.buttons["media.item.demo:familyMedia:family-1"]
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
        firstItem.tap()

        let closeButton = app.buttons["viewer.close"]
        let nextButton = app.buttons["下一个"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        nextButton.tap()

        let samplingDeadline = Date().addingTimeInterval(1)
        while Date() < samplingDeadline {
            XCTAssertTrue(
                closeButton.exists,
                "切换下一项时不应销毁全屏播放器并短暂露出媒体列表"
            )
            XCTAssertFalse(
                firstItem.isHittable,
                "切换下一项的准备阶段，底层媒体列表不应重新变为可操作状态"
            )
        }

        XCTAssertTrue(app.staticTexts["外婆的生日"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("viewer.surface", in: app).exists)
    }

    func testViewerSwipesBetweenPhotoAndVideoWithoutDismissal() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        app.buttons["media.item.demo:familyMedia:family-1"].tap()

        let viewer = element("viewer.surface", in: app)
        let closeButton = app.buttons["viewer.close"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForViewerItem("demo:familyMedia:family-1", in: app, timeout: 2))
        swipeViewer(.left, in: app)

        XCTAssertTrue(waitForViewerItem("demo:familyMedia:family-2", in: app, timeout: 4))
        XCTAssertTrue(closeButton.exists, "滑动下一项时应保留同一个全屏查看器")

        swipeViewer(.right, in: app)
        XCTAssertTrue(waitForViewerItem("demo:familyMedia:family-1", in: app, timeout: 4))
        XCTAssertTrue(closeButton.exists)
    }

    func testViewerSwipesDownToReturnToTheSameLibraryPosition() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        let item = app.buttons["media.item.demo:familyMedia:family-1"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        let viewer = element("viewer.surface", in: app)
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))
        swipeViewer(.down, in: app)

        XCTAssertTrue(
            item.waitForExistence(timeout: 4) && item.isHittable,
            "向下滑动应关闭查看器并回到原来的媒体列表位置"
        )
        XCTAssertFalse(app.buttons["viewer.close"].exists)
    }

    func testVideoViewerAlsoSwipesDownWithoutLeavingPlaybackUIBehind() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        let video = app.buttons["media.item.demo:familyMedia:family-2"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()

        let viewer = element("viewer.surface", in: app)
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 3))
        swipeViewer(.down, in: app)

        XCTAssertTrue(video.waitForExistence(timeout: 4) && video.isHittable)
        XCTAssertFalse(app.sliders.firstMatch.exists)
        XCTAssertFalse(app.buttons["viewer.close"].exists)
    }

    func testPhotoSlideshowCanPauseAndResume() {
        let app = makeApp(photoDurationSeconds: 10)
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        app.buttons["media.item.demo:familyMedia:family-1"].tap()

        let viewer = element("viewer.surface", in: app)
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))

        let playPause = element("viewer.playPause", in: app)
        XCTAssertTrue(playPause.exists)
        playPause.tap()
        XCTAssertTrue(waitForViewerItem("demo:familyMedia:family-1", in: app, timeout: 1))

        XCTAssertFalse(
            waitForViewerItem("demo:familyMedia:family-2", in: app, timeout: 11),
            "暂停照片轮播后不应自动前进"
        )
        XCTAssertTrue(waitForViewerItem("demo:familyMedia:family-1", in: app, timeout: 1))

        playPause.tap()
        XCTAssertTrue(
            waitForViewerItem("demo:familyMedia:family-2", in: app, timeout: 11),
            "恢复照片轮播后应从完整停留时间重新计时"
        )
    }

    func testViewerChromeAutoHidesAndReturnsOnPhotoTap() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        app.buttons["media.item.demo:familyMedia:family-1"].tap()

        let closeButton = app.buttons["viewer.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            closeButton.waitForNonExistence(timeout: 6),
            "照片查看时控制栏应自动隐藏"
        )

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 3),
            "轻点照片应重新显示关闭按钮与控制栏"
        )
    }

    func testPhotoViewerRemainsUsableAfterLandscapeRotation() {
        let app = makeApp()
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        app.buttons["media.item.demo:familyMedia:family-1"].tap()
        XCTAssertTrue(element("viewer.surface", in: app).waitForExistence(timeout: 3))

        XCUIDevice.shared.orientation = .landscapeLeft
        let viewer = element("viewer.surface", in: app)
        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft)
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))

        let closeButton = app.buttons["viewer.close"]
        let playPause = element("viewer.playPause", in: app)
        if !playPause.exists {
            viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        }

        XCTAssertTrue(
            playPause.waitForExistence(timeout: 2)
                && element("viewer.next", in: app).exists,
            "横屏旋转后底部控制栏不应被安全区裁切"
        )
        XCTAssertTrue(
            closeButton.exists,
            "横屏旋转后关闭入口仍应可用"
        )
    }

    func testJellyfinCardOpensDemoLibrary() {
        let app = makeApp()
        app.launch()

        element("media.source.jellyfin", in: app).tap()

        XCTAssertTrue(
            app.staticTexts["电影"].waitForExistence(timeout: 5),
            "Jellyfin 入口应能进入演示媒体库"
        )
        XCTAssertTrue(
            app.navigationBars["Jellyfin"].buttons["媒体"].exists,
            "首层媒体库应使用中文来源首页作为返回文案"
        )
    }

    func testSignedOutJellyfinCardRoutesDirectlyToSettings() {
        let app = makeApp(jellyfinSignedOut: true)
        app.launch()

        let jellyfin = element("media.source.jellyfin", in: app)
        XCTAssertTrue(jellyfin.waitForExistence(timeout: 3))
        jellyfin.tap()

        XCTAssertTrue(
            app.staticTexts["内容来源"].waitForExistence(timeout: 3),
            "冷启动首帧点击未登录的 Jellyfin 应进入设置，而不是进入空媒体库"
        )
        if element("ipad.sidebar", in: app).exists {
            XCTAssertTrue(element("ipad.sidebar.settings", in: app).isSelected)
        } else {
            XCTAssertTrue(app.tabBars.buttons["设置"].isSelected)
        }
    }

    func testEmptyFolderUsesFolderSpecificMessage() {
        let app = makeApp()
        app.launch()

        element("media.source.jellyfin", in: app).tap()
        let playlists = app.buttons["media.item.demo:jellyfin:playlists"]
        XCTAssertTrue(playlists.waitForExistence(timeout: 5))
        playlists.tap()

        XCTAssertTrue(
            app.staticTexts["这个文件夹暂时没有内容"].waitForExistence(timeout: 5),
            "空文件夹应使用文件夹语义，而不是笼统的媒体库提示"
        )
    }

    func testSettingsTabOpens() {
        let app = makeApp()
        app.launch()

        openSettings(in: app)

        XCTAssertTrue(app.staticTexts["内容来源"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["帮助与诊断"].exists)
    }

    func testDiagnosticsOffersSystemSettingsRecoveryPath() {
        let app = makeApp()
        app.launch()

        openSettings(in: app)
        element("settings.diagnostics", in: app).tap()

        XCTAssertTrue(
            element("diagnostics.open-system-settings", in: app)
                .waitForExistence(timeout: 3),
            "诊断页应提供本地网络权限的系统设置入口"
        )
    }

    func testFirstRunOnboardingCanBeDismissed() {
        let app = makeApp(showOnboarding: true)
        app.launch()

        XCTAssertTrue(app.staticTexts["欢迎使用家映"].waitForExistence(timeout: 3))
        app.buttons["先看看首页"].tap()
        XCTAssertTrue(element("media.source.family", in: app).waitForExistence(timeout: 3))
    }

    func testFirstRunPrimaryActionOpensSettingsAfterDismissal() {
        let app = makeApp(showOnboarding: true)
        app.launch()

        let configure = element("onboarding.configure", in: app)
        XCTAssertTrue(configure.waitForExistence(timeout: 3))
        XCTAssertTrue(configure.isHittable, "开始连接按钮的完整视觉区域应可点击")
        configure.tap()

        XCTAssertTrue(
            app.staticTexts["内容来源"].waitForExistence(timeout: 3),
            "欢迎页关闭后应可靠切换到设置页"
        )
    }

    func testFirstRunFeatureCardOpensConnectionSettings() {
        let app = makeApp(showOnboarding: true)
        app.launch()

        let feature = element("onboarding.jellyfin", in: app)
        XCTAssertTrue(feature.waitForExistence(timeout: 3))
        XCTAssertTrue(feature.isHittable, "欢迎页的连接介绍卡应可点击")
        feature.tap()

        XCTAssertTrue(
            app.staticTexts["内容来源"].waitForExistence(timeout: 3),
            "点击连接介绍卡后应进入设置页"
        )
    }

    func testMediaGridTilesDoNotOverlap() {
        let app = makeApp()
        app.launch()

        element("media.source.family", in: app).tap()
        element("media.category.all", in: app).tap()
        let first = app.buttons["media.item.demo:familyMedia:family-1"]
        let second = app.buttons["media.item.demo:familyMedia:family-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 5))

        XCTAssertFalse(
            first.frame.intersects(second.frame),
            "相邻媒体卡片的点击区域不得重叠：first=\(first.frame), second=\(second.frame)"
        )
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
    }

    func testAdaptiveRootUsesTheExpectedPrimaryNavigation() throws {
        let app = makeApp()
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let sidebar = element("ipad.sidebar", in: app)
        if sidebar.waitForExistence(timeout: 2) {
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            XCTAssertTrue(element("ipad.sidebar.home", in: app).isSelected)

            element("ipad.sidebar.family", in: app).tap()
            XCTAssertTrue(element("media.category.all", in: app).waitForExistence(timeout: 3))

            element("ipad.sidebar.jellyfin", in: app).tap()
            XCTAssertTrue(app.staticTexts["电影"].waitForExistence(timeout: 5))

            element("ipad.sidebar.settings", in: app).tap()
            XCTAssertTrue(app.staticTexts["内容来源"].waitForExistence(timeout: 3))
        } else {
            XCTAssertTrue(app.tabBars.buttons["媒体"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.tabBars.buttons["设置"].exists)
        }
    }

    func testIPadCategoryCardsAdaptWithoutLosingNavigation() throws {
        let app = makeApp()
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let sidebar = element("ipad.sidebar", in: app)
        guard sidebar.waitForExistence(timeout: 2) else {
            throw XCTSkip("此布局用例仅在 iPad 模拟器执行")
        }

        let familyDestination = element("ipad.sidebar.family", in: app)
        XCTAssertEqual(familyDestination.label, "家庭媒体")
        familyDestination.tap()

        let all = element("media.category.all", in: app)
        let videos = element("media.category.videos", in: app)
        let photos = element("media.category.photos", in: app)
        XCTAssertTrue(all.waitForExistence(timeout: 3))
        XCTAssertTrue(videos.exists)
        XCTAssertTrue(photos.exists)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForSameRow([all, videos, photos], timeout: 3))
        XCTAssertEqual(all.frame.height, videos.frame.height, accuracy: 1)
        XCTAssertEqual(videos.frame.height, photos.frame.height, accuracy: 1)
        assertNoOverlap([all, videos, photos])

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            waitForFeaturedLayout(
                featured: all,
                secondary: [videos, photos],
                timeout: 3
            )
        )
        assertNoOverlap([all, videos, photos])
        XCTAssertTrue(
            familyDestination.isSelected,
            "旋转后应保持家庭媒体来源和详情页面"
        )
    }

    private func makeApp(
        showOnboarding: Bool = false,
        jellyfinSignedOut: Bool = false,
        photoDurationSeconds: Int = 60
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-demo",
            "-familyMedia.playback.photoDurationSeconds",
            String(photoDurationSeconds)
        ]
        if showOnboarding {
            app.launchArguments.append("--ui-testing-show-onboarding")
        }
        if jellyfinSignedOut {
            app.launchArguments.append("--ui-testing-jellyfin-signed-out")
        }
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForViewerItem(
        _ itemID: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        element("viewer.currentItem.\(itemID)", in: app)
            .waitForExistence(timeout: timeout)
    }

    private func swipeViewer(_ direction: ViewerSwipeDirection, in app: XCUIApplication) {
        let viewer = element("viewer.surface", in: app)
        switch direction {
        case .left:
            viewer.swipeLeft(velocity: .fast)
        case .right:
            viewer.swipeRight(velocity: .fast)
        case .down:
            viewer.swipeDown(velocity: .fast)
        }
    }

    private func openSettings(in app: XCUIApplication) {
        let sidebarSettings = element("ipad.sidebar.settings", in: app)
        if sidebarSettings.exists {
            sidebarSettings.tap()
        } else {
            app.tabBars.buttons["设置"].tap()
        }
    }

    private func waitForSameRow(
        _ elements: [XCUIElement],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let midYs = elements.map(\.frame.midY)
            if let first = midYs.first,
               midYs.dropFirst().allSatisfy({ abs($0 - first) <= 2 }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func waitForFeaturedLayout(
        featured: XCUIElement,
        secondary: [XCUIElement],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let secondaryMidYs = secondary.map(\.frame.midY)
            if secondary.count == 2,
               featured.frame.maxY < secondary[0].frame.minY,
               abs(secondaryMidYs[0] - secondaryMidYs[1]) <= 2 {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func assertNoOverlap(
        _ elements: [XCUIElement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for firstIndex in elements.indices {
            for secondIndex in elements.indices where secondIndex > firstIndex {
                XCTAssertFalse(
                    elements[firstIndex].frame.intersects(
                        elements[secondIndex].frame
                    ),
                    file: file,
                    line: line
                )
            }
        }
    }
}

private enum ViewerSwipeDirection {
    case left
    case right
    case down
}
