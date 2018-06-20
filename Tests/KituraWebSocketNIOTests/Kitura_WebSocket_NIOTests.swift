import XCTest
@testable import KituraWebSocketNIO

final class Kitura_WebSocket_NIOTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Kitura_WebSocket_NIO().text, "Hello, World!")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
