//
//  MultiMapTaskTests.swift
//  
//
//  Created by 박병관 on 5/25/24.
//

import XCTest
@testable import Tetra
import Combine


final class MultiMapTaskTests: XCTestCase {

    func testSerial() throws {
        let input = (0..<100).map{ $0 }
        let expect = expectation(description: "completion")
        var buffer = [Int]()

        let cancellable = MultiMapTask(maxTasks: .max(1), upstream: input.publisher) {
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
    }
    
    func testSerialCancel() async throws {
        let input = (0..<100)
        let delay = 1_000_000 as UInt64
        let expect = expectation(description: "task cancellation")
        let pub = MultiMapTask(maxTasks: .max(1), upstream: input.publisher) { value in
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled {
                expect.fulfill()
            }
            return .success(value)
        }
        var bag = Set<AnyCancellable>()
        pub.sink { _ in
            
        } receiveValue: { _ in

        }.store(in: &bag)
        try await Task.sleep(nanoseconds: 2 * delay)
        bag.removeAll()
        await fulfillment(of: [expect], timeout: 0.5)
    }
    
    func testSerialFailure() async throws {
        let upstream = (0..<100).publisher.setFailureType(to: CancellationError.self)
        let delay = 1_000_000 as UInt64
        let expect = expectation(description: "task failure")
        let pub = MultiMapTask(maxTasks: .max(1), upstream: upstream, transform: { value in
            try? await Task.sleep(nanoseconds: delay)
            if value == 33 {
                return .failure(CancellationError()) as Result<Int,CancellationError>
            }
            return .success(value) as Result<Int,CancellationError>
        })
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
