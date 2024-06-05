//
//  NSManagedObjectContextTests.swift
//
//
//  Created by 박병관 on 6/5/24.
//

import XCTest
#if canImport(CoreData)
import CoreData
@testable import Tetra

final class NSManagedObjectContextTests: XCTestCase {


    func testBlocking() throws {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let uuid = UUID()
        let returnValue = context.tetra._performAndWait {
            return uuid
        }
        XCTAssertEqual(uuid, returnValue)
        let result = Result {
            try context.tetra._performAndWait {
                throw CancellationError()
            }
        }
        XCTAssertThrowsError(try result.get()) {
            XCTAssertTrue($0 is CancellationError, "\($0) is not \(CancellationError.self)")

        }
        
    }
    
    func testMainAsync() async throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let uuid = UUID()
        let returnValue = await context.tetra._performEnqueue {
            XCTAssertTrue(Thread.isMainThread)
            return uuid
        }
        XCTAssertEqual(uuid, returnValue)
        let result:Result<Void,any Error>
        do {
            try await context.tetra._performEnqueue{
                throw CancellationError()
            }
            result = .success(())
        } catch {
            result = .failure(error)
        }
        XCTAssertThrowsError(try result.get()) {
            XCTAssertTrue($0 is CancellationError, "\($0) is not \(CancellationError.self)")
        }
    }
    
    func testBackgroundAsync() async throws {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let uuid = UUID()
        let returnValue = await context.tetra._performEnqueue {
            XCTAssertFalse(Thread.isMainThread)
            return uuid
        }
        XCTAssertEqual(uuid, returnValue)
        let result:Result<Void,any Error>
        do {
            try await context.tetra._performEnqueue{
                throw CancellationError()
            }
            result = .success(())
        } catch {
            result = .failure(error)
        }
        XCTAssertThrowsError(try result.get()) {
            XCTAssertTrue($0 is CancellationError, "\($0) is not \(CancellationError.self)")
        }
    }
    
    
    func testImmediate() throws {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let completion = expectation(description: "completion")
        context.perform {
            defer { completion.fulfill() }
            let uuid = UUID()
            let expectValue = context.tetra._performImmediate {
                return uuid
            }
            XCTAssertEqual(expectValue, .success(uuid))
            let expectThrow = Result {
                try context.tetra._performImmediate {
                    throw CancellationError()
                }
            }
            func checkError() {
                XCTAssertThrowsError(try expectThrow.get()) {
                    XCTAssertTrue($0 is CancellationError, "\($0) is not \(CancellationError.self)")
                }
            }
            checkError()
        }
        
        let expectNil = context.tetra._performImmediate {
            
        }
        XCTAssertNil(expectNil)
        
        wait(for: [completion], timeout: 0.1)
        
    }
    
}

#endif
