//
//  AsyncSubscriberTests.swift
//  
//
//  Created by 박병관 on 5/31/24.
//

import XCTest
import Combine
@testable import Tetra


final class AsyncSubscriberTests: XCTestCase {

    func testNonThrowing() async {
        let source = Array(0..<100)
        var demandBuffer = [Subscribers.Demand]()
        let publisher = source.publisher.delay(for: 0.001, scheduler: DispatchQueue.main)
            .handleEvents(
                receiveRequest: {
                    XCTAssertEqual($0, .max(1))
                    demandBuffer.append($0)
                }
            )
        var array = [Int]()
        for await value in CompatAsyncPublisher(publisher: publisher) {
            array.append(value)
        }
        XCTAssertEqual(source, array)
        XCTAssertEqual(demandBuffer, .init(repeating: .max(1), count: 100))
    }
    
    func testThrowing() async throws {
        let source = Array(0..<100)
        let target = try XCTUnwrap(source.randomElement())
        let publisher = source.publisher.delay(for: 0.001, scheduler: DispatchQueue.main)
            .tryMap{
                if $0 == target {
                    throw CancellationError()
                } else {
                    return $0
                }
            }
            .handleEvents(
                receiveRequest: {
                    XCTAssertEqual($0, .max(1))
                }
            )
        var array = [Int]()
        do {
            for try await value in CompatAsyncThrowingPublisher(publisher: publisher) {
                array.append(value)
            }
            XCTFail("expected to throw error")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error) is not a CancellationError")
        }
        XCTAssertEqual(array.last, target-1)
    }


}
