import XCTest
@testable import AgentClientCore

final class RateLimitSnapshotFormatTests: XCTestCase {
    // MARK: - Happy path

    func test_format_withFullParams() {
        let params: [String: Any] = [
            "rateLimits": [
                "planType": "pro",
                "primary": [
                    "usedPercent": 0.45,
                    "windowDurationMins": 60,
                    "resetsAt": "2026-06-22T12:00:00Z"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: pro | Used: 45% | Window: 60m | Reset: 2026-06-22T12:00:00Z")
    }

    func test_format_withSecondaryResetFallback() {
        let params: [String: Any] = [
            "rateLimits": [
                "planType": "free",
                "primary": [
                    "usedPercent": 0.80,
                    "windowDurationMins": 1440
                ] as [String: Any],
                "secondary": [
                    "resetsAt": "2026-06-23T00:00:00Z"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: free | Used: 80% | Window: 1440m | Reset: 2026-06-23T00:00:00Z")
    }

    func test_format_withIntegerUsedPercent() {
        let params: [String: Any] = [
            "rateLimits": [
                "planType": "enterprise",
                "primary": [
                    "usedPercent": 99,
                    "windowDurationMins": 5
                ] as [String: Any]
            ] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: enterprise | Used: 99% | Window: 5m | Reset: ?")
    }

    // MARK: - Edge cases

    func test_format_withNilParams_returnsEmpty() {
        let result = RateLimitSnapshot.format(params: nil)
        XCTAssertEqual(result, "")
    }

    func test_format_withEmptyParams_returnsEmpty() {
        let result = RateLimitSnapshot.format(params: [:])
        XCTAssertEqual(result, "")
    }

    func test_format_withMissingRateLimitsKey_returnsEmpty() {
        let params: [String: Any] = ["foo": "bar"]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "")
    }

    func test_format_withMissingFields_usesDefaults() {
        let params: [String: Any] = [
            "rateLimits": [:] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: unknown | Used: ? | Window: ?m | Reset: ?")
    }

    func test_format_withUnknownPlanType() {
        let params: [String: Any] = [
            "rateLimits": [
                "planType": "😅"
            ] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: 😅 | Used: ? | Window: ?m | Reset: ?")
    }

    func test_format_withZeroUsedPercent() {
        let params: [String: Any] = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 0.0,
                    "resetsAt": "soon"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: unknown | Used: 0% | Window: ?m | Reset: soon")
    }

    func test_format_withVerySmallUsedPercent() {
        let params: [String: Any] = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 0.001,
                    "windowDurationMins": 1
                ] as [String: Any]
            ] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: unknown | Used: 0% | Window: 1m | Reset: ?")
    }

    func test_format_withLargeWindow() {
        let params: [String: Any] = [
            "rateLimits": [
                "planType": "max",
                "primary": [
                    "usedPercent": 50,
                    "windowDurationMins": 43200,
                    "resetsAt": "next-month"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let result = RateLimitSnapshot.format(params: params)
        XCTAssertEqual(result, "Plan: max | Used: 50% | Window: 43200m | Reset: next-month")
    }
}
