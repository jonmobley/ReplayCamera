//
//  MomentExportOptionTests.swift
//  ReplayTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import XCTest
@testable import Replay

final class MomentExportOptionTests: XCTestCase {

    func testAvailableIncludesOnlyFullWhenShort() {
        let options = MomentExportOption.available(forDuration: 12)
        XCTAssertEqual(options, [.full])
    }

    func testAvailableAddsThirtyWhenLongEnough() {
        let options = MomentExportOption.available(forDuration: 30)
        XCTAssertEqual(options, [.thirty, .full])
    }

    func testAvailableAddsSixtyWhenLongEnough() {
        let options = MomentExportOption.available(forDuration: 60)
        XCTAssertEqual(options, [.thirty, .sixty, .full])
    }

    func testSecondsToExportCapsTrailing() {
        XCTAssertEqual(
            MomentExportOption.thirty.secondsToExport(from: 12),
            12,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MomentExportOption.sixty.secondsToExport(from: 90),
            60,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MomentExportOption.full.secondsToExport(from: 90),
            90,
            accuracy: 0.001
        )
    }
}
