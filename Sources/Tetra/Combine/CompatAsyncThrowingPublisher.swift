//
//  CompatAsyncThrowingPublisher.swift
//  It's simply rewritten from OpenCombine/Concurrency with manual Mirror inspection
//  See https://github.com/OpenCombine/OpenCombine/tree/master/Sources/OpenCombine/Concurrency
//
//  Created by pbk on 2022/12/16.
//

import Foundation
@preconcurrency import Combine

public struct CompatAsyncThrowingPublisher<P:Publisher>: AsyncTypedSequence {

    public typealias AsyncIterator = Iterator
    
    public var publisher:P
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(source: publisher)
    }
    
    public struct Iterator: AsyncIteratorProtocol {
        
        public typealias Element = P.Output
        @usableFromInline
        internal let inner = AsyncSubscriber<P>()
        @usableFromInline
        internal let reference:AnyCancellable
        
        @inlinable
        public mutating func next() async throws -> P.Output? {
            let result = await withTaskCancellationHandler(operation: inner.next) { [reference] in
                reference.cancel()
            }
            switch result {
            case .failure(let failure):
                throw failure
            case .success(let success):
                return success
            case .none:
                return nil
            }
        }
        
        @usableFromInline
        internal init(source: P) {
            self.reference = AnyCancellable(inner)
            source.subscribe(inner)
        }
        
    }
    
    @inlinable
    public init(publisher: P) {
        self.publisher = publisher
    }

}
