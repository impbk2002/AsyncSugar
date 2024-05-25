//
//  TetraTests.swift
//  
//
//  Created by iquest1127 on 2022/12/19.
//

import XCTest
import os
@testable import Tetra
import Combine

final class TetraTests: XCTestCase {
    
    override func setUp() async throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() async throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }
    
    func testUnfairLockPrecondition() throws {
        if #available(iOS 16.0, tvOS 16.0, macCatalyst 16.0, macOS 13.0, watchOS 9.0, *) {
            let lock = OSAllocatedUnfairLock()
            lock.withLock {
                lock.precondition(.owner)
            }
            lock.precondition(.notOwner)
        } else {
            
            let lock = ManagedUnfairLock()
            lock.withLock {
                lock.precondition(.owner)
            }
            lock.precondition(.notOwner)
        }
    }

}
