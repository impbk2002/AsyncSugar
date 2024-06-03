//
//  CompatAsyncPublisher.swift
//  It's simply rewritten from OpenCombine/Concurrency with manual Mirror inspection
//  See https://github.com/OpenCombine/OpenCombine/tree/master/Sources/OpenCombine/Concurrency
//
//  Created by pbk on 2022/12/16.
//

import Foundation
@preconcurrency import Combine

public struct CompatAsyncPublisher<P:Publisher>: AsyncSequence where P.Failure == Never {

    public typealias AsyncIterator = Iterator
    public typealias Element = P.Output
    
    public var publisher:P
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(source: publisher)
    }
    
    @inlinable
    public init(publisher: P) {
        self.publisher = publisher
    }
    
    public struct Iterator: NonThrowingAsyncIteratorProtocol {
        
        public typealias Element = P.Output
        
        @usableFromInline
        internal let inner = AsyncSubscriber<P>()
        @usableFromInline
        internal let reference:AnyCancellable
        
        @inlinable
        public mutating func next() async -> P.Output? {
            let result = await withTaskCancellationHandler(operation: inner.next) { [reference] in
                reference.cancel()
            }
            switch result {
            case .none:
                return nil
            case .success(let value):
                return value
            }
        }
        
        @usableFromInline
        internal init(source: P) {
            self.reference = AnyCancellable(inner)
            source.subscribe(inner)
        }
        
    }
        
}


