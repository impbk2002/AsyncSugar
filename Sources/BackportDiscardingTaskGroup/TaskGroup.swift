//
//  TaskGroup.swift
//
//
//  Created by 박병관 on 6/20/24.
//

internal import CriticalSection

@usableFromInline
package func simuateDiscardingTaskGroup<T:Actor,TaskResult>(
    isolation actor: isolated T = #isolation,
    body: (isolated T, inout TaskGroup<Void>) async -> TaskResult
) async -> sending TaskResult {
    let wrapped = await withTaskGroup(of: Void.self, returning: Suppress<TaskResult>.self) { group in
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
        async let subTask:Void = { (act: isolated T) in
//            nonisolated(unsafe)
            var iter = suppress.base
            while let _ =  await iter.next(isolation: act) {
                if await holder.isFinished {
                    break
                }
            }
        }(actor)
        nonisolated(unsafe)
        let body2 = body
        async let mainTask = { (act: isolated T) in
            var iter = suppress.base
            let v = await body2(act, &iter)
            await holder.markDone()
            return Suppress(base: v)
        }(actor)
        await subTask
        let value = await mainTask.base
        return Suppress(base: value)
    }
    return wrapped.base
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
package func simuateDiscardingTaskGroup2<TaskResult>(
    isolation actor: isolated (any Actor)? = #isolation,
    body: (inout TaskGroup<Void>) async -> TaskResult
) async -> TaskResult {
    guard actor != nil else {
        preconditionFailure("actor should not be nil")
    }
    return await withoutActuallyEscaping(body) { escapingClosure in
        await __simuateDiscardingTaskGroup2(isolation: actor) { group in
            let value = await escapingClosure(&group)
            return Suppress(base: value)
        }
    }.base
}

@usableFromInline
internal func __simuateDiscardingTaskGroup2<TaskResult>(
    isolation actor: isolated (any Actor)?,
    body: @escaping (inout TaskGroup<Void>) async -> sending TaskResult
) async -> TaskResult {
    let wrapped:Suppress<TaskResult> = await withTaskGroup(of: Void.self, returning: Suppress<TaskResult>.self, isolation: actor) { group in
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
        async let subTask:Void = { (barrier: isolated (any Actor)?) in

            var iter = suppress.base
            while let _ = await iter.next(isolation: barrier) {
                if await holder.isFinished {
                    break
                }
            }
        }(actor)
        nonisolated(unsafe)
        let body2 = body
        async let mainTask = { (barrier: isolated (any Actor)?) in
            var iter = suppress.base
            let v = await body2(&iter)
            await holder.markDone()
            return Suppress(base: v)
        }(actor)
        do {
            // wait for subTask first to trigger priority elavation
            // (release finished tasks as soon as possible)
            await subTask
        }
        nonisolated(unsafe)
        let value = await mainTask.base

        return .init(base: value)
    }
    return wrapped.base
}

extension Suppress: BitwiseCopyable where Base: BitwiseCopyable {

}
