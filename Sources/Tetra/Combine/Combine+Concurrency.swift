//
//  Combine+Concurrency.swift
//  
//
//  Created by pbk on 2022/09/06.
//

import Foundation
import Combine

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
    func mapTask<T:Sendable>(transform: @escaping @isolated(any) @Sendable (Output) async -> T) -> MapTask<Self,T> where Output:Sendable {
        MapTask(upstream: self, transform: transform)
    }
    
    @inlinable
    func tryMapTask<T:Sendable>(transform: @escaping @isolated(any) @Sendable (Output) async throws -> T) -> TryMapTask<Self,T> where Output:Sendable {
        TryMapTask(upstream: self, transform: transform)
    }
    
    @_spi(Experimental)
    @inlinable
    func multiMapTask<T:Sendable>(maxTasks: Subscribers.Demand = .max(1), transform: @escaping @Sendable @isolated(any) (Output) async throws(Self.Failure) -> T) -> MultiMapTask<Self,T> where Output: Sendable {
        MultiMapTask(maxTasks: maxTasks, upstream: self, transform: transform)
    }
    

    
}

internal extension Publisher {
    
    func asyncFlatMap<Segment:AsyncSequence, Err:Error>(
        maxTasks: Subscribers.Demand = .unlimited,
        transform: @escaping @Sendable @isolated(any) (Output) async throws(Err) -> Segment
    ) -> AsyncFlatMap<Self, Segment, Err, any Error> where Output:Sendable {
        return AsyncFlatMap(maxTasks: maxTasks, upstream: self, transform: transform)
    }
    
}
