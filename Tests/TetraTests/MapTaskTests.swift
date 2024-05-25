//
//  MapTaskTests.swift
//  
//
//  Created by 박병관 on 5/24/24.
//

import XCTest
@testable import Tetra
import Combine


final class MapTaskTests: XCTestCase {

    nonisolated
    func testSerial() throws {
        let input = (0..<100).map{ $0 }
        let expect = expectation(description: "completion")
        var buffer = [Int]()

        let cancellable = MapTask(upstream: input.publisher) {
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
    }
    
    nonisolated
    func testCancel() throws {
        let input = (0..<100)
        let target = try XCTUnwrap(input.randomElement())
        let holder = UnsafeCancellableHolder()
        let lock = NSRecursiveLock()
        let expect = expectation(description: "task cancellation")
        let pub = MapTask(upstream: input.publisher) { value in
            if value == target {
                await withUnsafeContinuation{
                    lock.withLock {
                        holder.bag.removeAll()
                    }
                    $0.resume()
                }
                XCTAssertTrue(Task.isCancelled)
            }
            return value
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
    
    nonisolated
    func testFailure() throws {
        let sequence = (0..<100)
        let target = try XCTUnwrap(sequence.randomElement())
        let upstream = sequence.publisher.setFailureType(to: CancellationError.self)
        let expect = expectation(description: "task failure")
        let pub = MapTask(upstream: upstream, handler: { value in
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
