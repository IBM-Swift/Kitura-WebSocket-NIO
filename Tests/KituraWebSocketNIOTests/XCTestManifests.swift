import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(Kitura_WebSocket_NIOTests.allTests),
    ]
}
#endif