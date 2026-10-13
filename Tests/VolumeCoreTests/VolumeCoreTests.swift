import XCTest
@testable import VolumeCore

final class VolumeCoreTests: XCTestCase {
    func testClampingAndFineSteps() {
        var state = VolumeState(current: 99, maximum: 100)!
        state.apply(.up)
        XCTAssertEqual(state.current, 100)
        state.apply(.down, stepPercent: 6, fine: true)
        XCTAssertEqual(state.current, 99)
        for _ in 0..<100 { state.apply(.down) }
        XCTAssertEqual(state.current, 0)
    }

    func testMuteRestoresLastAudibleVolume() {
        var state = VolumeState(current: 42, maximum: 100)!
        state.apply(.mute)
        XCTAssertEqual(state.current, 0)
        state.apply(.mute)
        XCTAssertEqual(state.current, 42)
        state.apply(.down)
        state.apply(.mute)
        state.apply(.mute)
        XCTAssertEqual(state.current, 41)
    }

    func testConfigurableSteps() {
        for percentage in VolumeStep.supportedPercentages {
            var state = VolumeState(current: 10, maximum: 100)!
            state.apply(.up, stepPercent: percentage)
            XCTAssertEqual(state.current, 10 + percentage)
            state.apply(.down, stepPercent: percentage)
            XCTAssertEqual(state.current, 10)
        }
    }

    func testDefaultStepIsOnePercent() {
        var state = VolumeState(current: 10, maximum: 100)!
        state.apply(.up)
        XCTAssertEqual(state.current, 11)
        state.apply(.down)
        XCTAssertEqual(state.current, 10)
    }

    func testStoredStepValidation() {
        for percentage in VolumeStep.supportedPercentages {
            XCTAssertEqual(VolumeStep.validated(percentage), percentage)
        }
        for invalid in [-1, 0, 4, 100, Int.max] {
            XCTAssertEqual(VolumeStep.validated(invalid), 1)
        }
    }

    func testExtremeStepsAreSafelyClamped() {
        var state = VolumeState(current: 10, maximum: 100)!
        state.apply(.up, stepPercent: Int.max)
        XCTAssertEqual(state.current, 100)
        state.apply(.down, stepPercent: Int.min)
        XCTAssertEqual(state.current, 99)
    }

    func testInitialZeroUnmuteUsesConservativeFallback() {
        var state = VolumeState(current: 0, maximum: 100)!
        state.apply(.mute)
        XCTAssertEqual(state.current, 25)
    }

    func testNonstandardRange() {
        var state = VolumeState(current: 20, maximum: 40)!
        XCTAssertEqual(state.percent, 50)
        state.apply(.up, stepPercent: 5)
        XCTAssertEqual(state.current, 22)
        state.apply(.down, fine: true)
        XCTAssertEqual(state.current, 21)
        var tiny = VolumeState(current: 0, maximum: 1)!
        tiny.apply(.up)
        XCTAssertEqual(tiny.current, 1)
    }

    func testMuteRestoreSurvivesStateRefresh() {
        var original = VolumeState(current: 63, maximum: 100)!
        original.apply(.mute)
        var refreshed = VolumeState(current: 0, maximum: 100, restoreValue: original.restoreValue)!
        refreshed.apply(.mute)
        XCTAssertEqual(refreshed.current, 63)
        var smallerRange = VolumeState(current: 0, maximum: 40, restoreValue: 63)!
        smallerRange.apply(.mute)
        XCTAssertEqual(smallerRange.current, 40)
        XCTAssertEqual(VolumeState(current: 30, maximum: 100, restoreValue: 63)?.restoreValue, 30)
    }

    func testInvalidDDCValuesRejected() {
        XCTAssertNil(VolumeState(current: 0, maximum: 0))
        XCTAssertNil(VolumeState(current: 101, maximum: 100))
        XCTAssertNil(VolumeState(current: -1, maximum: 100))
        XCTAssertNil(VolumeState(current: 0, maximum: 65536))
    }

    func testSynchronizationPreservesMuteRestoreValue() {
        var state = VolumeState(current: 42, maximum: 100)!
        state.apply(.mute)
        state.synchronize(current: 0)
        state.apply(.mute)
        XCTAssertEqual(state.current, 42)
        state.synchronize(current: 60)
        state.apply(.mute)
        state.apply(.mute)
        XCTAssertEqual(state.current, 60)
    }

    let monitors = [MonitorIdentity(id: "a", name: "LG HDR 4K"), MonitorIdentity(id: "b", name: "DELL U2723QE")]

    func testUniqueNameMatch() {
        XCTAssertEqual(RouteMatcher.match(outputName: "  lg hdr 4k ", isDisplayOutput: true, displayOutputNames: ["LG HDR 4K", "DELL U2723QE"], monitors: monitors)?.id, "a")
    }

    func testNeverRoutesNonDisplayOutputEvenWithExplicitLink() {
        XCTAssertNil(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: false, displayOutputNames: ["LG HDR 4K", "DELL U2723QE"], monitors: monitors))
        XCTAssertNil(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: false, displayOutputNames: ["LG HDR 4K", "DELL U2723QE"], monitors: monitors, explicitID: "a"))
    }

    func testDoesNotGuessForUnmatchedName() {
        XCTAssertNil(RouteMatcher.match(outputName: "Unknown HDMI", isDisplayOutput: true, displayOutputNames: ["LG HDR 4K", "DELL U2723QE"], monitors: [monitors[0]]))
    }

    func testAmbiguousNameRequiresExplicitLink() {
        let identical = [monitors[0], MonitorIdentity(id: "c", name: "LG HDR 4K")]
        XCTAssertNil(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: true, displayOutputNames: ["LG HDR 4K", "DELL U2723QE"], monitors: identical))
        XCTAssertEqual(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: true, displayOutputNames: ["LG HDR 4K", "DELL U2723QE"], monitors: identical, explicitID: "c")?.id, "c")
    }

    func testDuplicateAudioNamesAreAmbiguousEvenWithOneDDCMonitor() {
        XCTAssertNil(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: true,
                                       displayOutputNames: ["LG HDR 4K", "lg hdr 4k"], monitors: [monitors[0]]))
        XCTAssertEqual(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: true,
                                         displayOutputNames: ["LG HDR 4K", "LG HDR 4K"],
                                         monitors: [monitors[0]], explicitID: "a")?.id, "a")
    }

    func testUnknownAudioInventoryDoesNotProveUniqueness() {
        XCTAssertNil(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: true,
                                       displayOutputNames: [], monitors: [monitors[0]]))
    }

    func testMissingExplicitLinkDoesNotFallBackToAnotherMonitor() {
        XCTAssertNil(RouteMatcher.match(outputName: "LG HDR 4K", isDisplayOutput: true, displayOutputNames: ["LG HDR 4K", "DELL U2723QE"], monitors: monitors, explicitID: "disconnected"))
    }

    func testMediaKeys() {
        let down = MediaKey.decode(data1: (0 << 16) | 0x0a00, subtype: 8)
        XCTAssertEqual(down?.action, .up)
        XCTAssertEqual(down?.isDown, true)
        XCTAssertEqual(down?.isRepeat, false)
        let up = MediaKey.decode(data1: (1 << 16) | 0x0b00, subtype: 8)
        XCTAssertEqual(up?.action, .down)
        XCTAssertEqual(up?.isDown, false)
        XCTAssertEqual(MediaKey.decode(data1: (7 << 16) | 0x0a01, subtype: 8)?.isRepeat, true)
        XCTAssertEqual(MediaKey.decode(data1: (7 << 16) | 0x0a00, subtype: 8)?.action, .mute)
    }

    func testOtherSystemEventsPassThrough() {
        XCTAssertNil(MediaKey.decode(data1: (16 << 16) | 0x0a00, subtype: 8)) // play/pause
        XCTAssertNil(MediaKey.decode(data1: (2 << 16) | 0x0a00, subtype: 8)) // brightness
        XCTAssertNil(MediaKey.decode(data1: 0x0a00, subtype: 1))
        XCTAssertNil(MediaKey.decode(data1: 0x0c00, subtype: 8))
    }
}
