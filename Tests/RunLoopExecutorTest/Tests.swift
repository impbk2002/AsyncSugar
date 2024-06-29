//
//  Tests.swift
//  
//
//  Created by 박병관 on 6/30/24.
//

@testable import CriticalSection
import Testing
import Foundation

@Suite
struct Tests {
    
    
    @Test
    func evaluate() async {
        if #available(macOS 14.0, *) {
            let myActor = await RunLoopActor()
            let block = { (act: isolated RunLoopActor) in
                
                #expect(RunLoopPriorityExecutor.myLocal != nil)
                
            }
            await block(myActor)
        } else {
            // Fallback on earlier versions
        }
    }
    
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)

actor RunLoopActor {
    
    let executor:RunLoopPriorityExecutor
    
    init() async {
        
        let ref:RunLoopPriorityExecutor = await withUnsafeContinuation { continuation in
            
            let th = Thread{
                executeRunloop {
                    continuation.resume(returning: $0)
                }

            }
            th.qualityOfService = .default
            th.start()
        }
        
        self.executor = ref
    }
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    
    
}
