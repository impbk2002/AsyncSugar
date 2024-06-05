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

public extension TetraExtension where Base: Publisher, Base.Failure == Never {
    
    @inlinable
    var values: WrappedAsyncSequence<Base.Output> {
        if #available(iOS 15.0, macOS 12.0, macCatalyst 15.0, tvOS 15.0, watchOS 8.0, *) {
            return WrappedAsyncSequence(base: base.values)
        } else {
            return WrappedAsyncSequence(base: CompatAsyncPublisher(publisher: base))
        }
    }
    
}

public extension TetraExtension where Base: Publisher {
    
    @inlinable
    var values: some AsyncTypedSequence<Base.Output> {
        if #available(iOS 15.0, macOS 12.0, macCatalyst 15.0, tvOS 15.0, watchOS 8.0, *) {
            return base.values
        } else {
            return CompatAsyncThrowingPublisher(publisher: base)
        }
    }
    
}

public extension Publisher {
    
    @inlinable
    func mapTask<T:Sendable>(transform: @escaping @Sendable (Output) async -> T) -> MapTask<Self,T> where Output:Sendable {
        MapTask(upstream: self, transform: transform)
    }
    
    @inlinable
    func tryMapTask<T:Sendable>(transform: @escaping @Sendable (Output) async throws -> T) -> TryMapTask<Self,T> where Output:Sendable {
        TryMapTask(upstream: self, transform: transform)
    }
    
    @_spi(Experimental)
    @inlinable
    func multiMapTask<T:Sendable>(maxTasks: Subscribers.Demand = .max(1), transform: @escaping @Sendable (Output) async -> Result<T,Failure>) -> MultiMapTask<Self,T> where Output: Sendable {
        MultiMapTask(maxTasks: maxTasks, upstream: self, transform: transform)
    }
    

}

public extension Publisher {
    
    @available(iOS, deprecated: 15.0, renamed: "values", message: "will be removed on Swift 6")
    @available(macCatalyst, deprecated: 15.0, renamed: "values", message: "will be removed on Swift 6")
    @available(tvOS, deprecated: 15.0, renamed: "values", message: "will be removed on Swift 6")
    @available(macOS, deprecated: 12.0, renamed: "values", message: "will be removed on Swift 6")
    @available(watchOS, deprecated: 8.0, renamed: "values", message: "will be removed on Swift 6")
    @inlinable
    var asyncSequence: some AsyncTypedSequence<Output> {
        return TetraExtension(self).values
    }
    
}

public extension Publisher where Failure == Never {
    
    @available(iOS, deprecated: 15.0, renamed: "values", message: "will be removed on Swift 6")
    @available(macCatalyst, deprecated: 15.0, renamed: "values", message: "will be removed on Swift 6")
    @available(tvOS, deprecated: 15.0, renamed: "values", message: "will be removed on Swift 6")
    @available(macOS, deprecated: 12.0, renamed: "values", message: "will be removed on Swift 6")
    @available(watchOS, deprecated: 8.0, renamed: "values", message: "will be removed on Swift 6")
    @inlinable
    var asyncSequence:WrappedAsyncSequence<Output> {
        return TetraExtension(self).values
    }
    
}
