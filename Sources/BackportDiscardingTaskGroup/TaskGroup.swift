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
    ) async -> V {
        let holder: SafetyRegion = actor as? SafetyRegion ?? .init()
        if await holder.isFinished {
            preconditionFailure("SafetyRegion is already used!")
        }
        addTask(priority: .background) {
            /// keep at least one child task alive
            /// so that subTask won't return
            await holder.hold()
            
        }
        let suppress = Suppress(base: self)
        /// drain all the finished or failed Task
        async let subTask:Void = {
            var iter = suppress.base
            while let _ =  await iter.next(isolation: actor) {
                if await holder.isFinished {
                    break
                }
            }
        }()
        nonisolated(unsafe)
        let block = body
        async let mainTask = {
            var iter = suppress.base
            let v = await block(actor, &iter)
            await holder.markDone()
            return Suppress(base: v)
        }()
        await subTask
        return await mainTask.base
    }
    
}

@inlinable
package func simuateDiscardingTaskGroup<T:Actor,TaskResult>(
    isolation actor: isolated T = #isolation,
    body: @Sendable (isolated T, inout TaskGroup<Void>) async -> sending TaskResult
) async -> sending TaskResult {
     await withTaskGroup(of: Void.self, returning: TaskResult.self) {
         await $0.simulateDiscarding(isolation: actor, body: body)
    }
}


/// simulate `DiscardingTaskGroup` and return the TaskResult
///
///  This function is a good workaround for globalActor isolated version of `simuateDiscardingTaskGroup`
///
///
///```
///await simuateDiscardingTaskGroup { @MainActor group in
///    group.addTask{ ... }
///    group.addTask{ ... }
///    group.addTask{ ... }
///    return 0
///}
///```
///
///
/// - precondition: body can not be nonisolated
/// - Parameter body: DiscardingTaskGroup body
/// - Returns: which is returned from body
/// - SeeAlso: withDiscardingTaskGroup(returning:body:)
@inlinable
package func simuateDiscardingTaskGroup<TaskResult>(
    body: @Sendable @isolated(any) (inout TaskGroup<Void>) async -> sending TaskResult
) async -> sending TaskResult {
    guard let actor = body.isolation else {
        preconditionFailure("body must be isolated")
    }
    return await simuateDiscardingTaskGroup(isolation: actor) { region, group in
        precondition(actor === region, "must be isolated on the inferred actor")
        nonisolated(unsafe)
        var unsafe = Suppress(base: group)
        let value =  await body(&unsafe.base)
        group = unsafe.base
        return value
    }
}
