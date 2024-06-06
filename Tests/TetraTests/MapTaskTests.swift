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
        var demandHistory = [Subscribers.Demand]()
        let expect = expectation(description: "completion")
        var buffer = [Int]()
        let publisher = input.publisher
            .handleEvents(
                receiveRequest: {
                    demandHistory.append($0)
                }
            )
        let cancellable = MapTask(upstream: publisher) {
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
    
    nonisolated
    func testCancel() throws {
        let input = (0..<100)
        let target = try XCTUnwrap(input.randomElement())
        let holder = UnsafeCancellableHolder()
        let lock = NSRecursiveLock()
        let expect = expectation(description: "task cancellation")
        
        let mapTask = MapTask(upstream: input.publisher) { value in
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
            mapTask.sink { _ in
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
    
    func testDedicate() throws {
        let subject = PassthroughSubject<Int,Never>()
        let completion = expectation(description: "completion")
        var outputHandle: (Int) -> Void = { _ in }
        var demandHandle: (Subscribers.Demand) -> Void = {
            XCTAssertEqual($0, .unlimited)
        }
        let warmup = expectation(description: "warmpup")
        
        let cancellable = subject
            .handleEvents(
                receiveRequest: {
                    XCTAssertEqual($0, .max(1))
                }
            )
            .mapTask { value in
                return value
            }
            .handleEvents(
            receiveSubscription: { subscription in
                XCTAssertEqual("\(subscription)", "MapTask")
                warmup.fulfill()
            },
            receiveOutput: { value in
                outputHandle(value)
                outputHandle = { _ in }
            },
            receiveCompletion: { comp in
                completion.fulfill()
            },
            receiveCancel: { XCTFail("cancellation is not a valid case") },
            receiveRequest: {
                demandHandle($0)
            }
        ).sink { _ in }
        wait(for: [warmup], timeout: 0.5)
        demandHandle = {
            XCTAssertEqual($0, .none)
        }
        defer {
            subject.send(completion: .finished)
            wait(for: [completion], timeout: 3)
            cancellable.cancel()
        }
        
        for _ in 0..<100 {
            let value = try XCTUnwrap((0..<19).randomElement())
            let expectValue = expectation(description: "receive \(value)")
            outputHandle = {
                XCTAssertEqual(value, $0)
                expectValue.fulfill()
            }
            demandHandle = {
                XCTAssertEqual($0, .none)
            }
            subject.send(value)
            wait(for: [expectValue], timeout: 0.3)
        }
    }
    

}
