//
//  ThrowingTaskGroup.swift
//
//
//  Created by 박병관 on 6/20/24.
//

@inlinable
package func simuateThrowingDiscardingTaskGroup<T:Actor,TaskResult>(
    isolation actor: isolated T,
    body: @Sendable (isolated T, inout ThrowingTaskGroup<Void, any Error>) async throws -> sending TaskResult
) async throws -> sending TaskResult {
    return try await withThrowingTaskGroup(of: Void.self, returning: TaskResult.self) { group in
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
            var iter = suppress.base
            while let _ = try await iter.next(isolation: actor) {
                if await holder.isFinished {
                    break
                }
            }
        }()
        async let mainTask = {
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
        let value = try await mainTask.base
        if let errorRef {
            throw errorRef
        }
        return value
    }
}

@inlinable
package func simuateThrowingDiscardingTaskGroup<TaskResult>(
    body: @isolated(any) (inout ThrowingTaskGroup<Void, any Error>) async throws -> sending TaskResult
) async throws -> sending TaskResult {
    guard let actor = body.isolation else {
        preconditionFailure("body must be isolated")
    }
    return try await simuateThrowingDiscardingTaskGroup(isolation: actor) { region, group in
        precondition(actor === region, "must be isolated on the inferred actor")
        nonisolated(unsafe)
        var unsafe = Suppress(base: group)
        do {
            let value = try await body(&unsafe.base)
            group = unsafe.base
            return value
        } catch {
            group = unsafe.base
            throw error
        }
    }
}
