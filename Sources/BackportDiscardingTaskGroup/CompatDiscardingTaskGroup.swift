//
//  CompatThrowingDiscardingTaskGroup.swift
//  
//
//  Created by 박병관 on 6/20/24.
//
@usableFromInline
package protocol CompatDiscardingTaskGroup<Err> {
    
    associatedtype Err:Error = any Error
    typealias Block = @isolated(any) @Sendable () async throws(Err) -> Void
    
    @inlinable
    var isCancelled:Bool { get }
    
    @inlinable
    var isEmpty:Bool { get }
    
    @inlinable
    func cancelAll()
    
    @inlinable
    mutating func addTaskUnlessCancelled(
        priority: TaskPriority?,
        operation: sending @escaping Block
    ) -> Bool
    
    @inlinable
    mutating func addTask(
        priority: TaskPriority?,
        operation: sending @escaping Block
    )
    
    @inlinable
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    mutating func addTask(
        executorPreference taskExecutor: (any TaskExecutor)?,
        priority: TaskPriority?,
        operation: sending @escaping Block
    )
    
    @inlinable
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    mutating func addTaskUnlessCancelled(
        executorPreference taskExecutor: (any TaskExecutor)?,
        priority: TaskPriority?,
        operation: sending @escaping Block
    ) -> Bool
    
}
