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

        let cancellable = TryMapTask(upstream: input.publisher) {
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
    
    func testCancel() async throws {
        let input = (0..<100)
        let delay = 1_000_000 as UInt64
        let expect = expectation(description: "task cancellation")
        let pub = TryMapTask(upstream: input.publisher) { value in
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled {
                expect.fulfill()
            }
            return value
        }
        var bag = Set<AnyCancellable>()
        pub.sink { _ in
            
        } receiveValue: { _ in

        }.store(in: &bag)
        try await Task.sleep(nanoseconds: 2 * delay)
        bag.removeAll()
        await fulfillment(of: [expect], timeout: 0.5)
    }
    
    func testFailure() async throws {
        let upstream = (0..<100).publisher.setFailureType(to: CancellationError.self)
        let delay = 1_000_000 as UInt64
        let expect = expectation(description: "task failure")
        let pub = TryMapTask(upstream: upstream) { value in
            try await Task.sleep(nanoseconds: delay)
            if value == 33 {
                throw CancellationError()
            }
            return value
        }
        var bag = Set<AnyCancellable>()
        pub.sink { completion in
            switch completion {
            case .finished:
                break
            case .failure(_):
                expect.fulfill()
            }
        } receiveValue: { _ in
        }.store(in: &bag)
        try await Task.sleep(nanoseconds: 2 * delay)
        await fulfillment(of: [expect], timeout: 0.5)
        bag.removeAll()
    }

}
