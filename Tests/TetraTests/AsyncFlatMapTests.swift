//
//  AsyncFlatMapTests.swift
//  
//
//  Created by 박병관 on 6/7/24.
//

import XCTest
import Combine
@testable import Tetra

final class AsyncFlatMapTests: XCTestCase {

    
    func testOrderd() throws {
        let completion = expectation(description: "complete")
        var array = [Int]()
        let sample = Array((0..<5))
        let bag = [0,1].publisher
            .handleEvents(
                receiveRequest: {
                    XCTAssertEqual($0, .max(1))
                }
            )
            .asyncFlatMap(maxTasks: .max(1)) { value in
                AsyncStream<Int>{ continuation in
                    sample.forEach{
                        continuation.yield($0)
                    }
                    continuation.finish()
                }.map{
                    await Task.yield()
                    return $0
                }
            }.handleEvents(
                receiveSubscription: {
                    XCTAssertEqual("\($0)", "AsyncFlatMap")
                }
            ).mapError{ $0.unwrap() }
            // ensure downstream do not request unlimited
            .buffer(size: 1, prefetch: .keepFull, whenFull: .customError{ fatalError() })
            .prefix(10)
            .sink { _ in
                completion.fulfill()
            } receiveValue: {
                array.append($0)
            }
        wait(for: [completion], timeout: 0.1)
        bag.cancel()
        XCTAssertEqual(array, sample + sample)
    }

    func testUnOrderd() throws {
        let completion = expectation(description: "complete")
        var array = [Int]()
        let sample = Array((0..<5))
        let lock = NSRecursiveLock()
        let bag = [0,1].publisher
            .handleEvents(
                receiveRequest: {
                    XCTAssertEqual($0, .max(2))
                }
            )
            .asyncFlatMap(maxTasks: .max(2)) { value in
                return AsyncStream<Int>{ continuation in
                    sample.forEach{
                        continuation.yield($0 + value * 10)
                    }
                    continuation.finish()
                }.map{
                    await Task.yield()
                    return $0
                }
            }.handleEvents(
                receiveSubscription: {
                    XCTAssertEqual("\($0)", "AsyncFlatMap")
                }
            ).mapError{ $0.unwrap() }
            .sink { _ in
                completion.fulfill()
            } receiveValue: { value in
                lock.withLock{
                    array.append(value)
                }
                
            }
        wait(for: [completion])
        bag.cancel()
        XCTAssertEqual(Set(array), [0,1,2,3,4,10,11,12,13,14])
    }
    
    func testCancelInTranform() throws {
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "cancellation")
        let lock = NSRecursiveLock()
        lock.withLock {
            (0..<5).publisher
                .asyncFlatMap(maxTasks: .unlimited) { value in
                    lock.withLock{
                        holder.bag = []
                    }
                    return AsyncStream<Int>{
                        $0.yield(value)
                        $0.finish()
                    }
                }.mapError{ $0.unwrap() }
                .handleEvents(
                    receiveCancel: {
                        completion.fulfill()
                    }
                ).sink { _ in
                    XCTFail("should not reach here")
                } receiveValue: { _ in
                    XCTFail("should not reach here")
                }.store(in: &holder.bag)
        }
        wait(for: [completion], timeout: 0.2)
    }
    
    func testCancelInSegment() throws {
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "cancellation")
        let lock = NSRecursiveLock()
        lock.withLock {
            (0..<5).publisher
                .asyncFlatMap(maxTasks: .unlimited) { value in
                    return AsyncStream<Int>{
                        $0.yield(value)
                        $0.finish()
                    }.map{
                        lock.withLock{
                            holder.bag = []
                        }
                        return $0
                    }
                }.mapError{ $0.unwrap() }
                .handleEvents(
                    receiveCancel: {
                        completion.fulfill()
                    }
                ).sink { _ in
                    XCTFail("should not reach here")
                } receiveValue: { _ in
                    XCTFail("should not reach here")
                }.store(in: &holder.bag)
        }
        wait(for: [completion], timeout: 0.2)
    }
    
    func testCancelInSubscriber() throws {
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "cancellation")
        let lock = NSRecursiveLock()
        lock.withLock {
            (0..<5).publisher
                .asyncFlatMap(maxTasks: .unlimited) { @Sendable value in
                    return AsyncStream<Int>{ @Sendable in
                        $0.yield(value)
                        $0.finish()
                    }
                }.mapError{
                    $0.unwrap()
                }.handleEvents(
                    receiveCancel: { @Sendable in
                        completion.fulfill()
                    }
                ).sink { _ in
                    XCTFail("should not reach here")
                } receiveValue: { _ in
                    lock.withLock{
                        holder.bag = []
                    }
                }.store(in: &holder.bag)
        }
        wait(for: [completion], timeout: 0.2)
    }
    
    
    @available(macOS 9999, *)
    func testThrowInTransformer() throws {
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "cancellation")
        (0..<5).publisher
            .asyncFlatMap(maxTasks: .max(1)) { value in
                if value == 3 {
                    throw CancellationError()
                }
                return AsyncStream<Int>{
                    $0.yield(value)
                    $0.finish()
                }
            }.mapError{
                switch $0 {
                case .transform(let error):
                    return error
                case .segment(let error):
                    XCTFail("should not throw during segment")
                    return error
                }
            }.sink {
                switch $0 {
                case .finished:
                    break
                case .failure(let error):
                    completion.fulfill()
                    XCTAssertTrue(error is CancellationError)
                }
            } receiveValue: {
                XCTAssertLessThan($0, 3)
            }.store(in: &holder.bag)
        wait(for: [completion], timeout: 0.2)
    }
    
    func testThrowInSegment() throws {
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "cancellation")
        (0..<5).publisher
            .asyncFlatMap(maxTasks: .max(1)) { value in
                return AsyncStream<Int>{
                    $0.yield(value)
                    $0.finish()
                }.map{
                    if $0 == 3 {
                        throw CancellationError()
                    }
                    return $0
                }
            }
            .mapError{
                switch $0 {
                case .segment(let error):
                    return error
                }
            }
            .sink {
                switch $0 {
                case .finished:
                    break
                case .failure(let error):
                    completion.fulfill()
                    XCTAssertTrue(error is CancellationError)
                }
            } receiveValue: {
                XCTAssertLessThan($0, 3)
            }.store(in: &holder.bag)
        wait(for: [completion], timeout: 0.2)
    }
    
    func testTransformUnsafeCancel() throws {
        // If Task cancellation occur in transformer, the returned Segment is responsible to handle the cancellation,
        // created Segment and transformer runs in the same task
        // UnsafeCurrentTask cancellation has no effect on root task
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "complete")
        var buffer = [Int]()
        (0..<5).publisher
            .asyncFlatMap(maxTasks: .max(1)) { value in
                if value == 0 {
                    withUnsafeCurrentTask{
                        $0?.cancel()
                    }
                }
                let transformTask = withUnsafeCurrentTask{ $0 }?.hashValue
                
                return AsyncStream<Int>{
                    await Task.yield()
                    withUnsafeCurrentTask {
                        XCTAssertEqual(transformTask, $0?.hashValue)
                    }
                    if Task.isCancelled {
                        return nil
                    }
                    withUnsafeCurrentTask{$0?.cancel()}
                    return value
                }
            }.mapError{
                $0.unwrap()
            }.sink { _ in
                completion.fulfill()
            } receiveValue: {
                buffer.append($0)
            }.store(in: &holder.bag)
        wait(for: [completion], timeout: 0.2)
        XCTAssertEqual(buffer, [1,2,3,4])
    }


}
