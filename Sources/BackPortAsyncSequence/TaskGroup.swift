//
//  TaskGroup.swift
//  
//
//  Created by 박병관 on 6/28/24.
//
import Namespace


public struct TypedTaskGroup<Element: Sendable> {
    
    @usableFromInline
    let base:TaskGroup<Element>
    
    @inlinable
    public init(base: TaskGroup<Element>) {
        self.base = base
    }
    
}

extension TypedTaskGroup: AsyncSequence, TypedAsyncSequence {
    
    public typealias Failure = Never
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(parent: base)
    }
    
    public struct Iterator {
        
        @usableFromInline
        var parent:TaskGroup<Element>
        
        @inlinable
        internal init(
            parent: TaskGroup<Element>
        ) {
            self.parent = parent
        }
        
    }
    
}

extension TypedTaskGroup.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Failure = Never
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async -> Element? {
        return await parent.next(isolation: actor)
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async -> Element? {
        await next(isolation: nil)
    }
    
}

extension TetraExtension{
    
    @inlinable
    public func bridge<T:Sendable>() -> TypedTaskGroup<T> where Base == TaskGroup<T> {
        return .init(base: base)
    }
    
}
