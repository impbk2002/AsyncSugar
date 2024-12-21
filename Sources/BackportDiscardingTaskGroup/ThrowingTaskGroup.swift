//
//  ThrowingTaskGroup.swift
//
//
//  Created by 박병관 on 6/20/24.
//

@inlinable
package func simuateThrowingDiscardingTaskGroup2<TaskResult>(
    isolation actor: isolated (any Actor)? = #isolation,
    body: (inout ThrowingTaskGroup<Void, any Error>) async throws -> TaskResult
) async throws -> TaskResult {
    guard actor != nil else {
        preconditionFailure("actor should not be nil")
    }
    return try await withoutActuallyEscaping(body) { escapingClosure in
        try await __simuateThrowingDiscardingTaskGroup2(isolation: actor) { group in
            let value = try await escapingClosure(&group)
            return Suppress(base: value)
        }
    }.base
}

@inlinable
package func simuateThrowingDiscardingTaskGroup<T:Actor,TaskResult>(
    isolation actor: isolated T,
    body: @Sendable (isolated T, inout ThrowingTaskGroup<Void, any Error>) async throws -> sending TaskResult
) async throws -> sending TaskResult {
    let wrapped:Suppress<TaskResult> = try await withThrowingTaskGroup(of: Void.self, returning: Suppress<TaskResult>.self, isolation: actor) { group in
        let holder: SafetyRegion = actor as? SafetyRegion ?? .init()
        if await holder.isFinished {
            preconditionFailure("SafetyRegion is already used!")
        }
        group.addTask(priority: .background) {
            /// keep at least one child task alive
            /// so that subTask won't return
            await holder.hold()
        }
        let suppress = Suppress(base: group)
        /// drain all the finished or failed Task
        async let subTask:Void = {
            nonisolated(unsafe)
            var iter = suppress.base
            while let _ = try await iter.next(isolation: actor) {
                if await holder.isFinished {
                    break
                }
            }
        }()
        async let mainTask = {
            nonisolated(unsafe)
            var iter = suppress.base
            do {
                let v = try await body(actor, &iter)
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
            group.cancelAll()
            errorRef = error
        }
        nonisolated(unsafe)
        let value = try await mainTask.base
        if let errorRef {
            throw errorRef
        }
        return Suppress(base: value)
    }
    return wrapped.base
}

@usableFromInline
internal func __simuateThrowingDiscardingTaskGroup2<TaskResult>(
    isolation actor: isolated (any Actor)?,
    body: @escaping (inout ThrowingTaskGroup<Void, any Error>) async throws -> sending TaskResult
) async throws -> TaskResult {
    let wrapped:Suppress<TaskResult> = try await withThrowingTaskGroup(of: Void.self, returning: Suppress<TaskResult>.self, isolation: actor) { group in
        let holder: SafetyRegion = actor as? SafetyRegion ?? .init()
        if await holder.isFinished {
            preconditionFailure("SafetyRegion is already used!")
        }
        group.addTask(priority: .background) {
            /// keep at least one child task alive
            /// so that subTask won't return
            await holder.hold()
        }
        let suppress = Suppress(base: group)
        /// drain all the finished or failed Task
        async let subTask:Void = {
            nonisolated(unsafe)
            var iter = suppress.base
            while let _ = try await iter.next(isolation: actor) {
                if await holder.isFinished {
                    break
                }
            }
        }()
        nonisolated(unsafe)
        let body2 = body
        nonisolated(unsafe)
        let block2 = { (barrier: isolated (any Actor)?) in
            nonisolated(unsafe)
            var iter = suppress.base
            return Suppress(base: try await body2(&iter))
        }
        async let mainTask = {
            do {
                let v = try await block2(actor)
                await holder.markDone()
                return v
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
            group.cancelAll()
            errorRef = error
        }
        nonisolated(unsafe)
        let value = try await mainTask.base
        if let errorRef {
            throw errorRef
        }
        return .init(base: value)
    }
    return wrapped.base
}
