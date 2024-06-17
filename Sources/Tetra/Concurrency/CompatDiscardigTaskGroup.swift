//
//  File.swift
//  
//
//  Created by 박병관 on 5/16/24.
//

import Foundation

internal protocol CompatThrowingDiscardingTaskGroup {
    
    var isCancelled:Bool { get }
    var isEmpty:Bool { get }
    func cancelAll()
    mutating func addTaskUnlessCancelled(
        priority: TaskPriority?,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Bool
    mutating func addTask(
        priority: TaskPriority?,
        operation: @escaping @Sendable () async throws -> Void
    )
    
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    mutating func addTask(executorPreference taskExecutor: (any TaskExecutor)?, priority: TaskPriority?, operation: @escaping @isolated(any) @Sendable () async throws -> Void)
    
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    mutating func addTaskUnlessCancelled(executorPreference taskExecutor: (any TaskExecutor)?, priority: TaskPriority?, operation: @escaping @isolated(any) @Sendable () async throws -> Void) -> Bool
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, macCatalyst 17.0, visionOS 1.0, *)
extension ThrowingDiscardingTaskGroup: CompatThrowingDiscardingTaskGroup {

}

extension ThrowingTaskGroup: CompatThrowingDiscardingTaskGroup where ChildTaskResult == Void, Failure == any Error {

}

/// Empty actor to isolate `ThrowingTaskGroup` to simulate DiscardingTaskGroup
@usableFromInline
actor SafetyRegion {
    
    @usableFromInline
    init() {
        
    }
    
}


extension ThrowingTaskGroup where ChildTaskResult == Void, Failure == any Error {
    
    /// work around for simulating Discarding TaskGroup
    ///
    ///  TaskGroup is protected by the actor isolation
    ///  - warning: always call TaskGroup api while holding isolation
    @usableFromInline
    internal mutating func simulateDiscarding(
        isolation actor: isolated (any Actor),
        body: (isolated any Actor, inout Self) async throws -> Void
    ) async throws {
        let lock = createCheckedStateLock(checkedState: DiscardingTaskState.waiting)
        addTask {
            // keep at least one child task alive
            try await withUnsafeThrowingContinuation { continuation in
                lock.withLock{
                    $0.transition(.suspend(continuation))
                }?.run()
            }
        }
        async let subTask:Void = {
            while let _ = try await next(isolation: actor) {

            }
        }()
        do {
            try await body(actor, &self)
            lock.withLock{
                $0.transition(.finish)
            }?.run()
            try await subTask
        } catch {
            lock.withLock{
                $0.transition(.cancel)
            }?.run()
            throw error
        }
    }
    
}

