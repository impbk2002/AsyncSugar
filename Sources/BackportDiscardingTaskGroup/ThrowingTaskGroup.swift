//
//  ThrowingTaskGroup.swift
//  
//
//  Created by 박병관 on 6/20/24.
//


extension ThrowingTaskGroup where ChildTaskResult == Void, Failure == any Error {
    
    /// work around for simulating Discarding TaskGroup
    ///
    ///  TaskGroup is protected by the actor isolation
    ///  - important: always call TaskGroup api while holding isolation
    @usableFromInline
    internal mutating func simulateDiscarding<T:Actor, V>(
        isolation actor: isolated T,
        body: (isolated T, inout Self) async throws -> sending V
    ) async throws -> V {
        let holder: SafetyRegion = actor as? SafetyRegion ?? .init()
        if await holder.isFinished {
            preconditionFailure("SafetyRegion is already used!")
        }
        addTask(priority: .background) {
            /// keep at least one child task alive
            /// so that subTask won't return
            await holder.hold()
        }
        /// drain all the finished or failed Task
        async let subTask:Void = {
            while let _ = try await next(isolation: actor) {
                if await holder.isFinished {
                    break
                }
            }
        }()
        async let mainTask = {
            do {
                let v = try await runBlock(isolation: actor, body:body)
                await holder.markDone()
                return Suppress(base: v)
            } catch {
                await holder.markDone()
                throw error
            }
        }()
        let errorRef:(any Error)?
        do {
            // wait for subTask first to trigger priority elavation
            // (release finished tasks as soon as possible)
            try await subTask
            errorRef = nil
        } catch {
            errorRef = error
        }
        let value = try await mainTask.base
        if let errorRef {
            throw errorRef
        }
        return value
    }
    
    @usableFromInline
    internal mutating func runBlock<T:Actor,V:~Copyable, ErrorRef:Error>(
        isolation actor: isolated T,
        body: (isolated T, inout Self) async throws(ErrorRef) -> sending V
    ) async throws(ErrorRef) -> sending V {
        try await body(actor, &self)
    }
    
}

@inlinable
package func simuateThrowingDiscardingTaskGroup<T:Actor,TaskResult>(
    isolation actor: isolated T,
    body: @Sendable (isolated T, inout ThrowingTaskGroup<Void, any Error>) async throws -> sending TaskResult
) async throws -> TaskResult {
    try await withThrowingTaskGroup(of: Void.self, returning: TaskResult.self) {
        try await $0.simulateDiscarding(isolation: actor, body: body)
    }
}


@inlinable
package func simuateThrowingDiscardingTaskGroup<TaskResult: Sendable>(
    body: @Sendable @isolated(any) (inout ThrowingTaskGroup<Void, any Error>) async throws -> sending TaskResult
) async throws -> sending TaskResult {
    guard let actor = body.isolation else {
        preconditionFailure("body must be isolated")
    }
    return try await simuateThrowingDiscardingTaskGroup(isolation: actor) { region, group in
        precondition(actor === region, "must be isolated on the inferred actor")
        nonisolated(unsafe)
        var unsafe = Suppress(base: group)
        defer { group = unsafe.base }
        return try await body(&unsafe.base)
    }
}


