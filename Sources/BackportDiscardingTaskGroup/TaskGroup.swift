//
//  TaskGroup.swift
//
//
//  Created by 박병관 on 6/20/24.
//

extension TaskGroup where ChildTaskResult == Void {
    
    /// work around for simulating Discarding TaskGroup
    ///
    ///  TaskGroup is protected by the actor isolation
    ///  - important: always call TaskGroup api while holding isolation
    @usableFromInline
    internal mutating func simulateDiscarding<T:Actor, V>(
        isolation actor: isolated T,
        body: (isolated T, inout Self) async  -> sending V
    ) async  -> V {
        let holder: SafetyRegion = actor as? SafetyRegion ?? .init()
        if await holder.isFinished {
            preconditionFailure("SafetyRegion is already used!")
        }
        addTask {
            /// keep at least one child task alive
            /// so that subTask won't return
            await holder.hold()
            
        }
        /// drain all the finished or failed Task
        async let subTask:Void = {
            while let _ =  await next(isolation: actor) {
                if await holder.isFinished {
                    break
                }
            }
        }()
        let value:V
        // wrap with do block so that `defer` pops before waiting subTask
        do {
            /// release suspending Task
            /// wrap the mutable TaskGroup with actor isolation
            value = await body(actor, &self)
            await holder.markDone()
        }
        await subTask
        return value
    }
    
}

@inlinable
package func simuateDiscardingTaskGroup<T:Actor,TaskResult>(
    isolation actor: isolated T = #isolation,
    body: @Sendable (isolated T, inout TaskGroup<Void>) async -> sending TaskResult
) async -> TaskResult {
     await withTaskGroup(of: Void.self, returning: TaskResult.self) {
         await $0.simulateDiscarding(isolation: actor, body: body)
    }
}


@inlinable
package func simuateDiscardingTaskGroup<TaskResult: Sendable>(
    body: @Sendable @isolated(any) (inout TaskGroup<Void>) async -> sending TaskResult
) async -> sending TaskResult {
    guard let actor = body.isolation else {
        preconditionFailure("body must be isolated")
    }
    return await simuateDiscardingTaskGroup(isolation: actor) { region, group in
        precondition(actor === region, "must be isolated on the inferred actor")
        nonisolated(unsafe)
        var unsafe = Suppress(base: group)
        defer { group = unsafe.base }
        return await body(&unsafe.base)
    }
}



