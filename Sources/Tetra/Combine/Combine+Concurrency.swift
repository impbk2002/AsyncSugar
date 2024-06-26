//
//  Combine+Concurrency.swift
//  
//
//  Created by pbk on 2022/09/06.
//

import Foundation
import Combine
internal import BackPortAsyncSequence

public extension Publisher {
    @inlinable
    var tetra:TetraExtension<Self> {
        .init(self)
    }
    
}

public extension TetraExtension where Base: Publisher {
    
    @inlinable
    var values: CompatAsyncThrowingPublisher<Base> {
        CompatAsyncThrowingPublisher(publisher: base)
    }
    
}

public extension Publisher {
    
    @inlinable
    func mapTask<T>(
        transform: @escaping @isolated(any) @Sendable (Output) async -> sending T
    ) -> some Publisher<T, Failure> where Output:Sendable {
        MapTask(upstream: self, transform: transform)
    }
    
    @inlinable
    func tryMapTask<T>(
        transform: @escaping @isolated(any) @Sendable (Output) async throws -> sending T
    ) -> some Publisher<T,any Error> where Output:Sendable {
        TryMapTask(upstream: self, transform: transform)
    }
    
    @_spi(Experimental)
    @inlinable
    func multiMapTask<T>(
        maxTasks: Subscribers.Demand = .max(1),
        transform: @escaping @Sendable @isolated(any) (Output) async throws(Failure) -> sending T
    ) -> some Publisher<T,Failure> where Output: Sendable {
        MultiMapTask(maxTasks: maxTasks, upstream: self, transform: transform)
    }
    

    
}


internal extension Publisher {
//    
//    func asyncFlatMap<Segment:AsyncSequence>(
//        maxTasks: Subscribers.Demand = .unlimited,
//        transform: @escaping @Sendable @isolated(any) (Output) async throws(any Error) -> sending Segment
//    ) -> AsyncFlatMap<Self,LegacyTypedAsyncSequence<Segment>> where Output:Sendable {
//        return AsyncFlatMap(maxTasks: maxTasks, upstream: self, transform: transform)
//    }
    
    func asyncFlatMap<Segment:TypedAsyncSequence>(
        maxTasks: Subscribers.Demand = .unlimited,
        transform: @escaping @Sendable @isolated(any) (Output) async throws(Failure) -> sending Segment
    ) -> AsyncFlatMap<Self,Segment> where Output:Sendable, Segment.Err == Failure {
        return AsyncFlatMap(maxTasks: maxTasks, upstream: self, transform: transform)
    }
    
}
