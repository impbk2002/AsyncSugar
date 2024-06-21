//
//  CompatThrowingDiscardingTaskGroup.swift
//  
//
//  Created by 박병관 on 6/20/24.
//
@usableFromInline
package protocol CompatDiscardingTaskGroup<Failure> {
    
    
    associatedtype Failure:Error = any Error
    typealias Block = @Sendable @isolated(any) () async throws(Failure) -> Void
    
    @inlinable
    var isCancelled:Bool { get }
    
    @inlinable
    var isEmpty:Bool { get }
    
    @inlinable
    func cancelAll()
    
    @inlinable
    mutating func addTaskUnlessCancelled(
        priority: TaskPriority?,
        operation: @escaping Block
    ) -> Bool
    
    @inlinable
    mutating func addTask(
        priority: TaskPriority?,
        operation: @escaping Block
    )
    
    @inlinable
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    mutating func addTask(
        executorPreference taskExecutor: (any TaskExecutor)?,
        priority: TaskPriority?,
        operation: @escaping Block
    )
    
    @inlinable
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    mutating func addTaskUnlessCancelled(
        executorPreference taskExecutor: (any TaskExecutor)?,
        priority: TaskPriority?,
        operation: @escaping Block
    ) -> Bool
    
}
