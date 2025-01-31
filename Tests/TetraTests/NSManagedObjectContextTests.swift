//
//  NSManagedObjectContextTests.swift
//
//
//  Created by 박병관 on 6/5/24.
//

import Testing
#if canImport(CoreData)
import CoreData
@testable import Tetra
internal import NamespaceExtension

@Suite
struct NSManagedObjectContextTests {


    @Test
    func testBlocking() throws {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let uuid = UUID()
        let returnValue = context.tetra._performAndWait {
            return uuid
        }
        #expect(uuid == returnValue)
        let result = Result {
            try context.tetra._performAndWait {
                throw CancellationError()
            }
        }
        #expect(throws: CancellationError.self, performing: {
            try result.get()
        })
        
    }
    
    @Test
    func testMainAsync() async throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let uuid = UUID()
        let returnValue = await context.tetra._performEnqueue {
            #expect(Thread.isMainThread)
            return uuid
        }
        #expect(uuid == returnValue)
        let result:Result<Void,any Error>
        do {
            try await context.tetra._performEnqueue{
                throw CancellationError()
            }
            result = .success(())
        } catch {
            result = .failure(error)
        }
        #expect(throws: CancellationError.self, performing: {
            try result.get()
        })
    }
    
    @Test
    func testBackgroundAsync() async throws {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let uuid = UUID()
        let returnValue = await context.tetra._performEnqueue {
            #expect(!Thread.isMainThread)
            return uuid
        }
        #expect(uuid == returnValue)
        let result:Result<Void,any Error>
        do {
            try await context.tetra._performEnqueue{
                throw CancellationError()
            }
            result = .success(())
        } catch {
            result = .failure(error)
        }
        #expect(throws: CancellationError.self) {
            try result.get()
        }
    }
    
    @Test
    func testImmediate() async throws {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let _:Void = await withUnsafeContinuation{ continuation in
            context.perform {
                defer {
                    continuation.resume()
                }
                let uuid = UUID()
                let expectValue = context.tetra._performImmediate {
                    return uuid
                }
                #expect(expectValue == .success(uuid))
                let expectThrow = Result {
                    try context.tetra._performImmediate {
                        throw CancellationError()
                    }
                }
                #expect(throws: CancellationError.self) {
                    try expectThrow.get()
                }
            }
            
            let expectNil = context.tetra._performImmediate {
                
            }
            #expect(expectNil == nil)
        }
        
    }
    
}

#endif
