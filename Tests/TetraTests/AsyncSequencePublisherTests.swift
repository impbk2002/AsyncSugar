//
//  File.swift
//  
//
//  Created by 박병관 on 5/25/24.
//

import Foundation
import XCTest
@testable import Tetra
import Combine
import BackPortAsyncSequence

class AsyncSequencePublisherTests: XCTestCase {
    
    
    func testSerial() throws {
        let expect = expectation(description: "completion")
        let source = (0..<100).map{ $0 }
        
        var buffer = [Int]()
        let stream = AsyncStream{ continuation in
            source.forEach{ continuation.yield($0) }
            continuation.finish()
        }
        let cancellable = AsyncTypedStream(base: stream)
            .tetra.publisher
            .catch{ _ in
                XCTFail()
                return Empty<Int, Never>()
            }
            .sink { _ in
                expect.fulfill()
            } receiveValue: {
                buffer.append($0)
            }
        wait(for: [expect], timeout: 0.5)
        cancellable.cancel()
        XCTAssertEqual(source, buffer)
    }
    
    func testCancel() throws {
        let input = (0..<100)
        let target = try XCTUnwrap(input.randomElement())
        let holder = UnsafeCancellableHolder()
        let lock = NSRecursiveLock()
        let expect = expectation(description: "task cancellation")
        let stream = AsyncStream{ continuation in
            input.forEach{ continuation.yield($0) }
            continuation.finish()
        }
        let asyncSequence = stream.map{ value in
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
        }
        let pub = AsyncSequencePublisher(base: LegacyTypedAsyncSequence(base: asyncSequence))
            .handleEvents(
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

        let expect = expectation(description: "task failure")
        let stream = AsyncStream{ continuation in
            sequence.forEach{ continuation.yield($0) }
            continuation.finish()
        }
        let asyncSequence = stream.map{ value in
            if value == target {
                throw CancellationError()
            }
            return value
        }
        let cancellable = AsyncSequencePublisher(base: LegacyTypedAsyncSequence(base: asyncSequence))
            .mapError{
                $0 as! CancellationError
            }
            
            .sink { completion in
                switch completion {
                case .finished:
                    XCTFail()
                case .failure:
                    expect.fulfill()
                }
            } receiveValue: {
                XCTAssertLessThanOrEqual($0, target)
            }
        wait(for: [expect], timeout: 0.5)
        cancellable.cancel()
    }
    
    
    
}
