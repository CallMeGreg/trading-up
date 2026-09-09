import XCTest

final class AudioSettingsUITests: XCTestCase {
    func testIndependentSlidersOneTapMuteAndRelaunchPersistence() {
        let app = XCUIApplication()
        app.launchEnvironment["TU_AUDIO_DISABLED"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 20))
        app.buttons["settings"].tap()
        let music = app.sliders["musicVolume"]
        let effects = app.sliders["sfxVolume"]
        XCTAssertTrue(music.waitForExistence(timeout: 10))
        XCTAssertTrue(effects.exists)

        music.adjust(toNormalizedSliderPosition: 0.32)
        effects.adjust(toNormalizedSliderPosition: 0.64)
        let musicLevel = app.staticTexts["musicVolumeLabel"].label
        let effectsLevel = app.staticTexts["sfxVolumeLabel"].label
        XCTAssertNotEqual(musicLevel, "Muted")
        XCTAssertNotEqual(effectsLevel, "Muted")

        app.buttons["sfxMute"].tap()
        XCTAssertEqual(app.staticTexts["sfxVolumeLabel"].label, "Muted")
        XCTAssertEqual(app.staticTexts["musicVolumeLabel"].label, musicLevel)
        XCTAssertEqual(app.buttons["sfxMute"].label, "Unmute SFX")
        app.buttons["sfxMute"].tap()
        XCTAssertEqual(app.staticTexts["sfxVolumeLabel"].label, effectsLevel)

        app.buttons["musicMute"].tap()
        XCTAssertEqual(app.staticTexts["musicVolumeLabel"].label, "Muted")
        XCTAssertEqual(app.staticTexts["sfxVolumeLabel"].label, effectsLevel)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 20))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.sliders["musicVolume"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["musicVolumeLabel"].label, "Muted")
        XCTAssertEqual(app.staticTexts["sfxVolumeLabel"].label, effectsLevel)
        app.buttons["musicMute"].tap()
        XCTAssertEqual(app.staticTexts["musicVolumeLabel"].label, musicLevel)

        app.sliders["musicVolume"].adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(app.staticTexts["musicVolumeLabel"].label, "Muted")
        app.buttons["musicMute"].tap()
        XCTAssertEqual(app.staticTexts["musicVolumeLabel"].label, musicLevel)
        XCTAssertTrue(app.switches["Haptics"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Music and SFX volume controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
