//
//  AsyncTypedSequence.swift
//  
//
//  Created by pbk on 2022/09/26.
//

import Combine
import _Concurrency
import Foundation

/***
 Entry point of TypeFailure for `AsyncFlatMap` and `AsyncSequencePublisher

 Since generalized `AsyncSequence` is not available until Swift 6, this `protocol` is a entry point for async typed throw.

Even though it has isolation parameter, this parameter is rarely used since `AsyncFlatMap` and `AsyncSequencePublisher` runs in nonisolated Task space.

`Use `WrappedAsyncSequence`  or  `WrappedAsyncSequenceV2` if possible which provides general implementation to adapt this protocol

 - postcondition: `Failure` must be same as `AsyncIterator.Failure`
 
 
 - adapting protocol to existing type,
 
 adapting protocols to exisiting type that user don't own is pretty easy too. By writing conformance like below, compiler now know the correct implemenation without recursive problem.
````
 extension AsyncStream.Iterator: TypedAsyncIteratorProtocol {
     
     @_implements(TypedAsyncIteratorProtocol, next(isolation:))
     mutating public func tetraNext(isolation actor: isolated (any Actor)?) async throws(Never) -> Self.Element? {
         if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
             var c: some AsyncIteratorProtocol<Element, TetraFailure> = self
             defer {
                 self = c as! Self
             }
             return await c.next(isolation: actor)
         } else {
             return try? await next()
         }
     }
     
 }

 ````
 */
public protocol TypedAsyncIteratorProtocol<Element, Failure> {
    
    associatedtype Element
    associatedtype Failure: Error

    
    @inlinable
    mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element?

}

public protocol TypedAsyncSequence<Element, Failure>: AsyncSequence where AsyncIterator: TypedAsyncIteratorProtocol {}


public protocol TypedAsyncIteratorProtocol2: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
}


public extension TypedAsyncIteratorProtocol {
    
    @inlinable
    mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
}



