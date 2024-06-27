//
//  Combine+Concurrency.swift
//  
//
//  Created by pbk on 2022/09/06.
//

import Foundation
import Combine
internal import BackPortAsyncSequence
import Namespace



public extension TetraExtension where Base: Publisher {
    
    @inlinable
    var values: CompatAsyncThrowingPublisher<Base> {
        CompatAsyncThrowingPublisher(publisher: base)
    }
    
}

public extension Publisher {
    
    @inlinable
    func mapTask<T>(
        priority: TaskPriority? = nil,
        transform: @escaping @isolated(any) @Sendable (Output) async -> sending T
    ) -> some Publisher<T, Failure> where Output:Sendable {
        MapTask(priority: priority, upstream: self, transform: transform)
    }
    
    @inlinable
    func tryMapTask<T>(
        priority: TaskPriority? = nil,
        transform: @escaping @isolated(any) @Sendable (Output) async throws -> sending T
    ) -> some Publisher<T,any Error> where Output:Sendable {
        TryMapTask(priority: priority, upstream: self, transform: transform)
    }
    
    @_spi(Experimental)
    @inlinable
    func multiMapTask<T>(
        priority: TaskPriority? = nil,
        maxTasks: Subscribers.Demand = .max(1),
        transform: @escaping @Sendable @isolated(any) (Output) async throws(Failure) -> sending T
    ) -> some Publisher<T,Failure> where Output: Sendable {
        MultiMapTask(priority: priority, maxTasks: maxTasks, upstream: self, transform: transform)
    }
    

    
}


internal extension Publisher {

    func asyncFlatMap<Segment:TypedAsyncSequence>(
        maxTasks: Subscribers.Demand = .unlimited,
        priority: TaskPriority? = nil,
        transform: @escaping @Sendable @isolated(any) (Output) async throws(Failure) -> sending Segment
    ) -> AsyncFlatMap<Self,Segment> where Output:Sendable, Segment.Err == Failure {
        return AsyncFlatMap(
            priority: priority,
            maxTasks: maxTasks,
            upstream: self,
            transform: transform
        )
    }
    
}

