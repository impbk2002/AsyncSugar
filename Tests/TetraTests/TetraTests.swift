//
//  TetraTests.swift
//  
//
//  Created by iquest1127 on 2022/12/19.
//

import Testing
import os
@testable import Tetra
import Combine
import CriticalSection

@Suite
struct TetraTests {
    
    @Test
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


