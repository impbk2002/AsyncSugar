//
//  MultiMapTaskTests.swift
//  
//
//  Created by 박병관 on 5/25/24.
//

import XCTest
@testable @_spi(Experimental) import Tetra
import Combine


final class MultiMapTaskTests: XCTestCase {

    func testSerial() throws {
        let input = (0..<100).map{ $0 }
        let expect = expectation(description: "completion")
        var buffer = [Int]()
        var demandHistory = [Subscribers.Demand]()
        let publisher = input.publisher.handleEvents(
            receiveRequest: { demandHistory.append($0) }
        )
        let cancellable = MultiMapTask(maxTasks: .max(1), upstream: publisher) {
            await Task.yield()
            return .success($0)
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
    
    func testSerialCancel() throws {
        let input = (0..<100)
        let holder = UnsafeCancellableHolder()
        let target = try XCTUnwrap(input.randomElement())
        let lock = NSRecursiveLock()
        let expect = expectation(description: "task cancellation")
        let pub = MultiMapTask(maxTasks: .max(1), upstream: input.publisher) { value in
            if value == target {
                await withUnsafeContinuation {
                    lock.withLock {
                        holder.bag.removeAll()
                    }
                    $0.resume()
                }
                XCTAssertTrue(Task.isCancelled)
            }
            return .success(value)
        }.handleEvents(
            receiveCancel: { expect.fulfill() }
        )
        lock.withLock {
            pub.sink { _ in
                XCTFail()
            } receiveValue: {
                XCTAssertLessThanOrEqual($0, target)
            }.store(in: &holder.bag)
        }


        wait(for: [expect], timeout: 0.5)
    }
    
    func testSerialFailure() throws {
        let sequence = (0..<100)
        let target = try XCTUnwrap(sequence.randomElement())
        let upstream = sequence.publisher.setFailureType(to: CancellationError.self)
        let expect = expectation(description: "task failure")
        let pub = MultiMapTask(maxTasks: .max(1), upstream: upstream, transform: { value in
            if value == target {
                return .failure(CancellationError()) as Result<Int,CancellationError>
            }
            return .success(value) as Result<Int,CancellationError>
        })
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
    
    

}
