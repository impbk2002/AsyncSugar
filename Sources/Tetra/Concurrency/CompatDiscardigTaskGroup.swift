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
    
    private var isFinished = false
    private var continuation: UnsafeContinuation<Void,Never>? = nil
    
    @usableFromInline
    init() {
        
    }
    
    @usableFromInline
    func markDone() {
        guard !isFinished else { return }
        isFinished = true
        continuation?.resume()
        continuation = nil
    }
    
    @usableFromInline
    func hold() async {
        await withUnsafeContinuation {
            if isFinished {
                $0.resume()
            } else {
                if let old = self.continuation {
                    assertionFailure("received suspend more than once!")
                    old.resume()
                }
                self.continuation = $0
            }
        }
    }
    
}


extension ThrowingTaskGroup where ChildTaskResult == Void, Failure == any Error {
    
    /// work around for simulating Discarding TaskGroup
    ///
    ///  TaskGroup is protected by the actor isolation
    ///  - important: always call TaskGroup api while holding isolation
    @usableFromInline
    internal mutating func simulateDiscarding(
        isolation actor: isolated (SafetyRegion),
        body: (isolated any Actor, inout Self) async throws -> Void
    ) async throws {
        addTask {
            /// keep at least one child task alive
            /// so that subTask won't return
            await actor.hold()
        }
        /// drain all the finished or failed Task
        async let subTask:Void = {
            while let _ = try await next(isolation: actor) {
            }
        }()
        // wrap with do block so that `defer` pops before waiting subTask
        do {
            /// release suspending Task
            defer { actor.markDone() }
            /// wrap the mutable TaskGroup with actor isolation
            try await body(actor, &self)
        }
        try await subTask
    }
    
}

