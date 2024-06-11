//
//  CompatAsyncThrowingPublisher.swift
//  It's simply rewritten from OpenCombine/Concurrency with manual Mirror inspection
//  See https://github.com/OpenCombine/OpenCombine/tree/master/Sources/OpenCombine/Concurrency
//
//  Created by pbk on 2022/12/16.
//

import Foundation
@preconcurrency import Combine

public struct CompatAsyncThrowingPublisher<P:Publisher>: AsyncSequence, TypedAsyncSequence {

    public typealias AsyncIterator = Iterator
    public typealias Failure = AsyncIterator.Failure
    
    public var publisher:P
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(source: publisher)
    }
    
    public struct Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
        
        public typealias Element = P.Output
        public typealias Failure = P.Failure
        @usableFromInline
        internal let inner = AsyncSubscriber<P>()
        @usableFromInline
        internal let reference:AnyCancellable
        
        @inlinable
        public mutating func next(isolation actor: isolated (any Actor)?) async throws(P.Failure) -> P.Output? {
            let result = await withTaskCancellationHandler { [inner] in
                await inner.next(isolation: actor)
            } onCancel: { [reference] in
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
