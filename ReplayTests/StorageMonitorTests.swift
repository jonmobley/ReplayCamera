//
//  StorageMonitorTests.swift
//  ReplayTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import XCTest
@testable import Replay

final class StorageMonitorTests: XCTestCase {

    func testIsLowWhenBelowThreshold() {
        XCTAssertTrue(
            StorageMonitor.isLowOnSpace(
                freeBytes: 100 * 1024 * 1024,
                threshold: 800 * 1024 * 1024
            )
        )
    }

    func testIsNotLowWhenAboveThreshold() {
        XCTAssertFalse(
            StorageMonitor.isLowOnSpace(
                freeBytes: 2 * 1024 * 1024 * 1024,
                threshold: 800 * 1024 * 1024
            )
        )
    }

    func testIsNotLowWhenFreeBytesUnknown() {
        XCTAssertFalse(StorageMonitor.isLowOnSpace(freeBytes: nil))
    }

    func testFreeDiskBytesReadableOnSimulator() {
        XCTAssertNotNil(StorageMonitor.freeDiskBytes())
    }
}
