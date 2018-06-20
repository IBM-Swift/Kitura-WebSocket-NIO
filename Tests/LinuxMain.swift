import XCTest

import KituraNIOWebSocketTests

var tests = [XCTestCaseEntry]()
tests += Kitura_WebSocket_NIOTests.allTests()
XCTMain(tests)
