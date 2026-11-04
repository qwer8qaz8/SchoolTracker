import Foundation

#if !canImport(XCTest)
public class XCTestCase {
    public init() {}
}

public enum XCTestFailureTracker {
    public nonisolated(unsafe) static var failures: [String] = []

    public static func record(_ message: String, file: StaticString, line: UInt) {
        let fileName = URL(fileURLWithPath: "\(file)").lastPathComponent
        failures.append("\(fileName):\(line): \(message)")
    }
}

public func XCTFail(_ message: String = "Assertion failed", file: StaticString = #filePath, line: UInt = #line) {
    XCTestFailureTracker.record(message, file: file, line: line)
}

public func XCTAssertTrue(
    _ expression: @autoclosure () throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        if !(try expression()) {
            let msg = message()
            XCTFail(msg.isEmpty ? "XCTAssertTrue failed" : msg, file: file, line: line)
        }
    } catch {
        XCTFail("Unexpected error thrown: \(error)", file: file, line: line)
    }
}

public func XCTAssertFalse(
    _ expression: @autoclosure () throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        if try expression() {
            let msg = message()
            XCTFail(msg.isEmpty ? "XCTAssertFalse failed" : msg, file: file, line: line)
        }
    } catch {
        XCTFail("Unexpected error thrown: \(error)", file: file, line: line)
    }
}

public func XCTAssertEqual<T: Equatable>(
    _ expression1: @autoclosure () throws -> T,
    _ expression2: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let lhs = try expression1()
        let rhs = try expression2()
        if lhs != rhs {
            let msg = message()
            let detail = "XCTAssertEqual failed: (\(lhs)) is not equal to (\(rhs))"
            XCTFail(msg.isEmpty ? detail : "\(detail) - \(msg)", file: file, line: line)
        }
    } catch {
        XCTFail("Unexpected error thrown: \(error)", file: file, line: line)
    }
}

public func XCTAssertEqual<T: FloatingPoint>(
    _ expression1: @autoclosure () throws -> T,
    _ expression2: @autoclosure () throws -> T,
    accuracy: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let lhs = try expression1()
        let rhs = try expression2()
        if abs(lhs - rhs) > accuracy {
            let msg = message()
            let detail = "XCTAssertEqualWithAccuracy failed: (\(lhs)) is not equal to (\(rhs)) +/- (\(accuracy))"
            XCTFail(msg.isEmpty ? detail : "\(detail) - \(msg)", file: file, line: line)
        }
    } catch {
        XCTFail("Unexpected error thrown: \(error)", file: file, line: line)
    }
}

public func XCTAssertNotNil(
    _ expression: @autoclosure () throws -> Any?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        if (try expression()) == nil {
            let msg = message()
            XCTFail(msg.isEmpty ? "XCTAssertNotNil failed" : msg, file: file, line: line)
        }
    } catch {
        XCTFail("Unexpected error thrown: \(error)", file: file, line: line)
    }
}

public func XCTAssertThrowsError<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) {
    do {
        _ = try expression()
        let msg = message()
        XCTFail(msg.isEmpty ? "XCTAssertThrowsError failed: did not throw error" : msg, file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
#endif
