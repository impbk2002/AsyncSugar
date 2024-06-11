//
//  AsyncTypedSequence.swift
//  
//
//  Created by pbk on 2022/09/26.
//

import Combine
import _Concurrency
import Foundation


/// Entry point of TypeFailure for `AsyncFlatMap` and `AsyncSequencePublisher
///
/// Since generalized `AsyncSequence` is not available until Swift 6, this `protocol` is a entry point for async typed throw. 
///
///Even though it has isolation parameter, this parameter is rarely used since `AsyncFlatMap` and `AsyncSequencePublisher` runs in nonisolated Task space.
///
/// `Use `WrappedAsyncSequence`  or  `WrappedAsyncSequenceV2` if possible which provides general implementation to adapt this protocol
///
/// - postcondition: `TetraFailure` must be same as `Failure`
public protocol TypedAsyncIteratorProtocol: AsyncIteratorProtocol {
    
    associatedtype TetraFailure: Error = any Error

    @inlinable
    mutating func tetraNext(isolation actor: isolated (any Actor)?) async throws(TetraFailure) -> Element?

}



@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public extension TypedAsyncIteratorProtocol where TetraFailure == Failure {
    
    @inlinable
    mutating func tetraNext(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        return try await next(isolation: actor)
    }
    
}

