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
    
    func testSerialCancel() throws {
        let input = (0..<100)
        let holder = UnsafeCancellableHolder()
        let target = try XCTUnwrap(input.randomElement())
        let lock = NSRecursiveLock()
        let expect = expectation(description: "task cancellation")
        let pub = MultiMapTask(maxTasks: .max(1), upstream: input.publisher) { value in
            if value == target {
                await withUnsafeContinuation {
//                    lock.withLock {
                        holder.bag.removeAll()
//                    }
                    $0.resume()
                }
                XCTAssertTrue(Task.isCancelled)
            }
            return value
        }.handleEvents(
            receiveCancel: {
                print("CAll")
                expect.fulfill()
            }
        )
        lock.withLock {
            pub.sink { _ in
                XCTFail()
            } receiveValue: {
                XCTAssertLessThanOrEqual($0, target)
            }.store(in: &holder.bag)
        }
        
        
        wait(for: [expect])
    }
    
    func testSerialFailure() throws {
        let sequence = (0..<100)
        let target = try XCTUnwrap(sequence.randomElement())
        let upstream = sequence.publisher.setFailureType(to: CancellationError.self)
        let expect = expectation(description: "task failure")
        let block:@Sendable (Int) async throws(CancellationError) -> sending Int = {
            if $0 == target {
                try Result<Void,CancellationError>.failure(CancellationError()).get()
            }
            await Task.yield()
            return $0
        }
        let pub = MultiMapTask(maxTasks: .max(1), upstream: upstream, transform: block)
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
    
    
    func testMultiDeamnd() throws {
        let warmup = expectation(description: "warmup")
        let subject = PassthroughSubject<Int,Never>()
        var _subscription: (any Subscription)? = nil
        var valueHandle: (Int) -> Void = { _ in }
        let subscriber = AnySubscriber<Int,Never>(
            receiveSubscription: {
                XCTAssertEqual("\($0)", "MultiMapTask")
                _subscription = $0
                warmup.fulfill()
            },
            receiveValue: {
                valueHandle($0)
                return .none
            },
            receiveCompletion: nil
        )
        var upstreamDemandHandle:(Subscribers.Demand) -> Void = {
            XCTAssertEqual($0, .none)
        }
        subject
            .handleEvents(
                receiveRequest: { demand in
                    upstreamDemandHandle(demand)
                }
            )
            .multiMapTask(maxTasks: .max(3)) {
                await Task.yield()
                return $0
            }.subscribe(subscriber)
        wait(for: [warmup])
        let subscription = try XCTUnwrap(_subscription)
        defer { subject.send(completion: .finished) }
        let expect1 = expectation(description: "wait for prefetching demand")
        upstreamDemandHandle = {
            XCTAssertEqual($0, .max(3))
            expect1.fulfill()
        }
        subscription.request(.max(4))
        wait(for: [expect1])
        let expect2 = expectation(description: "wait for remaining demand")
        let valueExpect = expectation(description: "wait for value 4 times")
        valueExpect.expectedFulfillmentCount = 4
        upstreamDemandHandle = {
            XCTAssertEqual($0, .max(1))
            expect2.fulfill()
        }
        valueHandle = { a in
            valueExpect.fulfill()
        }
        subject.send(0)
        subject.send(1)
        subject.send(2)
        wait(for: [expect2], timeout: 0.1)
        subject.send(3)
        wait(for: [valueExpect], timeout: 0.1)
    }
    
    
    func testInverseCompletion() throws {
        let warmup = expectation(description: "warmup")
        let completion = expectation(description: "completion")
        let subject = PassthroughSubject<Int,Never>()
        let count = 23
        let expectValue = expectation(description: "expect to fufill \(count) times")
        expectValue.expectedFulfillmentCount = count
        let cancellable = subject
            .handleEvents(
                receiveCompletion: { _ in
                    completion.fulfill()
                }
            )
            .multiMapTask(maxTasks: .unlimited) {
                try? await Task.sleep(nanoseconds: 1_000)
                return $0
            }
            .handleEvents(
                receiveSubscription: { _ in
                    warmup.fulfill()
                }
            )
            .sink { _ in
                expectValue.fulfill()
            }
        wait(for: [warmup], timeout: 0.1)
        (0..<count).forEach(subject.send)
        subject.send(completion: .finished)
        wait(for: [completion, expectValue], timeout: 0.1, enforceOrder: true)
        cancellable.cancel()
    }
    
    
}
