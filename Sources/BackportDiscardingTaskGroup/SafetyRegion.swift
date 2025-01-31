//
//  SafetyRegion.swift
//  
//
//  Created by 박병관 on 6/20/24.
//

/// Empty actor to isolate `ThrowingTaskGroup` to simulate DiscardingTaskGroup
@usableFromInline
package actor SafetyRegion {
    
    @usableFromInline
    internal(set) package var isFinished = false
    @usableFromInline
    internal var continuation: UnsafeContinuation<Void,Never>? = nil
    
    @inlinable
    package init() {
        
    }
    
    @usableFromInline
    package func markDone() {
//        guard !isFinished else { return }
        isFinished = true
        continuation?.resume()
        continuation = nil
    }
    
    @usableFromInline
    internal func hold() async {
        return await withUnsafeContinuation {
            if isFinished {
                $0.resume()
            } else {
                if let old = self.continuation {
                    assertionFailure("received suspend more than once!")
                    old.resume()
                }
                self.continuation = $0
            }
        }
    }
    
}
