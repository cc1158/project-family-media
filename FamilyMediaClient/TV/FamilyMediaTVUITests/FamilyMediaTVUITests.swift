import XCTest

@MainActor
final class FamilyMediaTVUITests: XCTestCase {
    func testFamilyMediaCardOpensCategories() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(element("home.category.all", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("home.category.videos", in: app).exists)
        XCTAssertTrue(element("home.category.photos", in: app).exists)
    }

    func testFamilyLibraryOpensTimelineModePicker() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("home.category.all", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)

        let browseMode = element("media.browseMode", in: app)
        XCTAssertTrue(
            browseMode.waitForExistence(timeout: 5),
            "家庭媒体列表应提供目录、月份和年份入口"
        )

        let firstItem = element("media.item.demo:familyMedia:family-1", in: app)
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
        if !firstItem.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(waitForFocus(firstItem, timeout: 3), "首张照片应获得初始焦点")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(
            waitForFocus(browseMode, timeout: 3),
            "向上应聚焦展示方式按钮"
        )
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(
            element("media.browseMode.month", in: app).waitForExistence(timeout: 3),
            "按下展示方式按钮后应打开目录、月份和年份选择面板"
        )
        XCTAssertTrue(element("media.browseMode.year", in: app).exists)
    }

    func testSettingsCardOpens() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right, forDuration: 0.1)
        XCUIRemote.shared.press(.right, forDuration: 0.1)
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(
            app.staticTexts["连接家里的媒体服务，调整适合你的播放方式"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["帮助与诊断"].exists)
    }

    func testSignedOutJellyfinCardRoutesDirectlyToSettings() {
        let app = makeApp(jellyfinSignedOut: true)
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right, forDuration: 0.1)
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(
            app.staticTexts["连接家里的媒体服务，调整适合你的播放方式"]
                .waitForExistence(timeout: 3),
            "冷启动首帧选择未登录的 Jellyfin 应进入设置，而不是进入空媒体库"
        )
    }

    func testViewerSupportsHiddenRemoteNavigation() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("home.category.all", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)

        let firstItem = element("media.item.demo:familyMedia:family-1", in: app)
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
        if !firstItem.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(waitForFocus(firstItem, timeout: 3), "首张照片应获得初始焦点")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("viewer.screen", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right, forDuration: 0.1)
        XCUIRemote.shared.press(.down, forDuration: 0.1)

        XCTAssertTrue(
            app.staticTexts["外婆的生日"].waitForExistence(timeout: 3),
            "控制栏隐藏时按右键应切换到下一项"
        )
    }

    func testViewerDismissRestoresOriginalCardFocus() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("home.category.all", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)

        let firstItem = element("media.item.demo:familyMedia:family-1", in: app)
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5), "应显示首张演示照片")
        if !firstItem.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(waitForFocus(firstItem, timeout: 3), "首张照片应获得初始焦点")
        XCUIRemote.shared.press(.select)
        let viewer = element("viewer.screen", in: app)
        XCTAssertTrue(viewer.waitForExistence(timeout: 3), "应打开照片查看器")
        XCUIRemote.shared.press(.menu)

        XCTAssertTrue(viewer.waitForNonExistence(timeout: 3), "Menu 应关闭照片查看器")
        XCTAssertTrue(firstItem.waitForExistence(timeout: 3), "关闭后应返回媒体列表")
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"),
            object: firstItem
        )
        let focusResult = XCTWaiter.wait(for: [focusExpectation], timeout: 3)
        let focusedElements = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true"))
            .allElementsBoundByIndex
            .map { "\($0.elementType.rawValue):\($0.identifier):\($0.label)" }
            .joined(separator: ", ")
        XCTAssertEqual(
            focusResult,
            .completed,
            "退出查看器后应恢复到原来的媒体卡片；当前焦点：\(focusedElements)"
        )
    }

    func testVideoViewerNoLongerExposesCustomScrubberOrSkipButtons() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("home.category.all", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            element("media.item.demo:familyMedia:family-1", in: app)
                .waitForExistence(timeout: 5)
        )

        XCUIRemote.shared.press(.right, forDuration: 0.1)
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.staticTexts["外婆的生日"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["后退 10 秒"].exists)
        XCTAssertFalse(app.buttons["前进 10 秒"].exists)
        XCTAssertFalse(element("viewer.timeline.slider", in: app).exists)
    }

    func testSystemVideoViewerDismissesBackToTheSelectedCard() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("home.category.all", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)

        let videoItem = element("media.item.demo:familyMedia:family-2", in: app)
        XCTAssertTrue(videoItem.waitForExistence(timeout: 5))
        let firstItem = element("media.item.demo:familyMedia:family-1", in: app)
        XCTAssertTrue(firstItem.exists)
        if !firstItem.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(waitForFocus(firstItem, timeout: 3), "首张照片应获得初始焦点")
        XCUIRemote.shared.press(.right, forDuration: 0.1)
        XCTAssertTrue(waitForFocus(videoItem, timeout: 3), "演示视频应获得焦点")
        XCUIRemote.shared.press(.select)

        let viewer = element("viewer.screen", in: app)
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["外婆的生日"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.menu)

        XCTAssertTrue(viewer.waitForNonExistence(timeout: 3))
        XCTAssertTrue(videoItem.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(videoItem, timeout: 3), "退出系统播放器后应恢复视频卡片焦点")
    }

    func testHiddenViewerSurfaceReopensControlsWithoutButtonOverlay() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("home.category.all", in: app).waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        let firstItem = element("media.item.demo:familyMedia:family-1", in: app)
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
        if !firstItem.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(waitForFocus(firstItem, timeout: 3), "首张照片应获得初始焦点")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("viewer.screen", in: app).waitForExistence(timeout: 3))

        XCTAssertTrue(
            app.buttons["下一个"].waitForNonExistence(timeout: 7),
            "照片控制栏应按既有策略自动隐藏"
        )
        XCTAssertFalse(
            app.buttons["显示播放控制"].exists,
            "隐藏控制栏时不应再创建会产生全屏玻璃焦点效果的 Button"
        )

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.buttons["下一个"].waitForExistence(timeout: 3),
            "按下 Select 应重新显示照片控制栏；当前焦点：\(focusedElements(in: app))"
        )
    }

    func testFirstRunOnboardingCanBeDismissed() {
        let app = makeApp(showOnboarding: true)
        app.launch()

        XCTAssertTrue(app.staticTexts["欢迎使用家映"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element("home.family", in: app).waitForExistence(timeout: 3))
    }

    private func makeApp(
        showOnboarding: Bool = false,
        jellyfinSignedOut: Bool = false
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
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

    private func waitForFocus(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func focusedElements(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true"))
            .allElementsBoundByIndex
            .map { "\($0.elementType.rawValue):\($0.identifier):\($0.label)" }
            .joined(separator: ", ")
    }
}
