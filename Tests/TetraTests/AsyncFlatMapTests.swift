//
//  AsyncFlatMapTests.swift
//  
//
//  Created by 박병관 on 6/7/24.
//

import XCTest
import Combine
import AsyncAlgorithms
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
            .setFailureType(to: Error.self)
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
            )
            .sink { _ in
                completion.fulfill()
            } receiveValue: {
                array.append($0)
            }
        wait(for: [completion])
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
            .setFailureType(to: Error.self)
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
            )
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
                .setFailureType(to: Error.self)
                .asyncFlatMap(maxTasks: .unlimited) { value in
                    lock.withLock{
                        holder.bag = []
                    }
                    return AsyncStream<Int>{
                        $0.yield(value)
                        $0.finish()
                    }
                }.handleEvents(
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
                .setFailureType(to: Error.self)
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
                }.handleEvents(
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
                .setFailureType(to: Error.self)
                .asyncFlatMap(maxTasks: .unlimited) { value in
                    return AsyncStream<Int>{
                        $0.yield(value)
                        $0.finish()
                    }
                }.handleEvents(
                    receiveCancel: {
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
    
    
    func testThrowInTransformer() throws {
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "cancellation")
        (0..<5).publisher
            .setFailureType(to: Error.self)
            .asyncFlatMap(maxTasks: .max(1)) { value in
                if value == 3 {
                    throw CancellationError()
                }
                return AsyncStream<Int>{
                    $0.yield(value)
                    $0.finish()
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
            .setFailureType(to: Error.self)
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
    
    func testTransformUnsafeCancel() throws {
        // If Task cancellation occur in transformer, the returned Segment is responsible to handle the cancellation,
        // created Segment and transformer runs in the same task
        // UnsafeCurrentTask cancellation has no effect on root task
        let holder = UnsafeCancellableHolder()
        let completion = expectation(description: "complete")
        var buffer = [Int]()
        (0..<5).publisher
            .setFailureType(to: Error.self)
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
            }.sink { _ in
                completion.fulfill()
            } receiveValue: {
                buffer.append($0)
            }.store(in: &holder.bag)
        wait(for: [completion], timeout: 0.2)
        XCTAssertEqual(buffer, [1,2,3,4])
    }


}
