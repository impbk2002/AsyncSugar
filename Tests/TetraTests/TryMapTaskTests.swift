//
//  TryMapTaskTests.swift
//  
//
//  Created by 박병관 on 5/25/24.
//

import XCTest
@testable import Tetra
import Combine


final class TryMapTaskTests: XCTestCase {

    func testSerial() throws {
        let input = (0..<100).map{ $0 }
        let expect = expectation(description: "completion")
        var buffer = [Int]()
        var demandHistory = [Subscribers.Demand]()
        let publisher = input.publisher.handleEvents(
            receiveRequest: { demandHistory.append($0) }
        )
        let cancellable = TryMapTask(upstream: publisher) {
            await Task.yield()
            return $0
        }.sink { _ in
            expect.fulfill()
        } receiveValue: {
            buffer.append($0)
        }
        wait(for: [expect], timeout: 0.5)
        cancellable.cancel()
        XCTAssertEqual(input, buffer)
        XCTAssertEqual(demandHistory, .init(repeating: .max(1), count: 100))
    }
    
    func testCancel() throws {
        let input = (0..<100)
        let target = try XCTUnwrap(input.randomElement())
        let ref = UnsafeCancellableHolder()
        let expect = expectation(description: "task cancellation")
        let pub = TryMapTask(upstream: input.publisher) { value in
            if value == target {
                await withUnsafeContinuation{ continuation in
                    ref.bag.removeAll()
                    continuation.resume()
                }
                XCTAssertTrue(Task.isCancelled)
            }
            return value
        }.handleEvents(
            receiveCancel: {
                expect.fulfill()
            }
        )
        pub.sink { _ in
            XCTFail()
        } receiveValue: {
            XCTAssertLessThanOrEqual($0, target)
        }.store(in: &ref.bag)
        wait(for: [expect], timeout: 0.5)
        
    }
    
    func testFailure() throws {
        let sequence = (0..<100)
        let target = try XCTUnwrap(sequence.randomElement())
        let upstream = sequence.publisher.setFailureType(to: CancellationError.self)
        let expect = expectation(description: "task failure")
        let pub = TryMapTask(upstream: upstream) { value in
            if value == target {
                throw CancellationError()
            }
            return value
        }
        
        var bag = Set<AnyCancellable>()
        pub.sink { completion in
            switch completion {
            case .finished:
                XCTFail()
            case .failure(_):
                expect.fulfill()
            }
        } receiveValue: {
            XCTAssertLessThanOrEqual($0, target)
        }.store(in: &bag)
        wait(for: [expect], timeout: 0.5)
        bag.removeAll()
    }
    
    func testUnsafeCancel() throws {
        let completion = expectation(description: "completion")
        var array = [Int]()
        let token = (0..<100)
            .publisher
            .tryMapTask { value in
                await Task.yield()
                withUnsafeCurrentTask {
                    $0?.cancel()
                }
                return value
            }.buffer(size: 1, prefetch: .keepFull, whenFull: .customError{ fatalError() })
            .sink { _ in
                completion.fulfill()
            } receiveValue: {
                array.append($0)
            }
        wait(for: [completion], timeout: 0.2)
        XCTAssertEqual(array, Array(0..<100))
        token.cancel()
    }

}
