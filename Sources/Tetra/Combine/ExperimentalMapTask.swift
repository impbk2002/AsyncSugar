//
//  File.swift
//  
//
//  Created by 박병관 on 5/15/24.
//

import Foundation
@preconcurrency import Combine
internal import CriticalSection
internal import BackportDiscardingTaskGroup

/**
    Manage Multiple Child Task. provides similair behavior of `flatMap`'s `maxPublisher`
    
    precondition `maxTasks` must be none zero value
 */
@_spi(Experimental)
public struct MultiMapTask<Upstream:Publisher, Output>: Publisher where Upstream.Output:Sendable {
    
    public typealias Output = Output
    public typealias Failure = Upstream.Failure
    public typealias Transformer = @Sendable @isolated(any) (Upstream.Output) async throws(Failure) -> sending Output

    public var priority:TaskPriority? = nil
    public var maxTasks:Subscribers.Demand
    public let upstream:Upstream
    public let transform: Transformer
    public let taskExecutor: (any Executor)?
    
    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        let processor = Inner(maxTasks: maxTasks, subscriber: subscriber, transform: transform)
        let task = if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *), let executor = taskExecutor as? (any TaskExecutor) {
            Task(executorPreference: executor, priority: priority, operation: processor.run)
        } else {
            Task(priority: priority, operation: processor.run)
        }
        processor.resumeCondition(task)
        upstream.subscribe(processor)
    }
    
    
    public init(
        priority: TaskPriority? = nil,
        maxTasks: Subscribers.Demand = .max(1),
        upstream: Upstream,
        transform: @escaping Transformer
    ) {
        precondition(maxTasks != .none, "maxTasks can not be zero")
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = transform
        self.taskExecutor = nil
        self.priority = priority
    }
    
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public init(
        priority:TaskPriority? = nil,
        maxTasks: Subscribers.Demand = .max(1),
        executor:(any TaskExecutor)? = nil,
        upstream: Upstream,
        transform: @escaping Transformer
    ) {
        precondition(maxTasks != .none, "maxTasks can not be zero")
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = transform
        self.taskExecutor = executor
        self.priority = priority
    }
    
}

extension MultiMapTask: Sendable where Upstream: Sendable {}

extension MultiMapTask {

    struct TaskState<S:Subscriber> where S.Failure == Failure, S.Input == Output {
        var demand = PendingDemandState()
        var subscriber:S? = nil
        var upstreamSubscription = AsyncSubscriptionState.waiting
        var condition = TaskValueContinuation.waiting
    }
    
    // this can run serially or in parallel by using demand config, so use adding actor isolation seems quite odd here
    struct Inner<S:Subscriber>: CustomCombineIdentifierConvertible where S.Failure == Failure, S.Input == Output {
        
        private let maxTasks:Subscribers.Demand
        private let valueSource = AsyncStream<Result<Upstream.Output, Failure>>.makeStream()
        // accessed from Combine intferface or isolated Actor
        // which ever guarantee serialized access
        private let state: some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: TaskState<S>())
        private let transform:Transformer
        let combineIdentifier = CombineIdentifier()
        
        init(
            maxTasks:Subscribers.Demand,
            subscriber:S,
            transform: @escaping Transformer
        ) {
            self.maxTasks = maxTasks
            self.transform = transform
            state.withLockUnchecked{
                $0.subscriber = subscriber
            }
        }
        
//        private func prepareTermination(cancel:Bool) {
//            let effect = state.withLockUnchecked {
//                let effect1 = $0.condition.transition(cancel ? .cancel : .finish)
//                let effect2 = $0.upstreamSubscription.transition(cancel ? .cancel : .finish)
//                return (effect1, effect2)
//            }
//            effect.0?.run()
//            effect.1?.run()
//        }
        
        internal func localTask(
            isolation actor: isolated (any Actor)? = #isolation,
            group: inout some CompatDiscardingTaskGroup<NoThrow>
        ) async {
            let barrier = actor as? SafetyRegion ?? SafetyRegion()
            
            for await event in valueSource.stream {
                if await barrier.isFinished {
                    break
                }
                switch event {
                case .failure(let failure):
                    await barrier.markDone()
                    // no contention except `request` and `cancel`
                    await send(barrier: barrier, completion: .failure(failure), cancel: false)
                    break
                case .success(let success):
                    let flag = group.addTaskUnlessCancelled(priority: nil) {
                        do throws(Failure) {
                            let value = try await transform(success)
                            do {
                                // no contention except `request` and `cancel`
                                try await send(isolation: barrier, value)
                            } catch {
                                await barrier.markDone()
                            }
                        } catch {
                            await barrier.markDone()
                            // no contention except `request` and `cancel`
                            await send(barrier: barrier, completion: .failure(error), cancel: true)
                        }
                    }
                    if !flag {
                        break
                    }
                }
            }
        }
        
        private func terminateStream() {
            valueSource.continuation.finish()
        }
        
        private func send(
            barrier: isolated (some Actor)? = #isolation,
            completion: Subscribers.Completion<Failure>,
            cancel:Bool = false
        ) {
            terminateStream()
            let (subscriber, taskEffect) = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let taskEffect = if cancel {
                    $0.condition.transition(.cancel)
                } else {
                    $0.condition.transition(.finish)
                }
                return (old, taskEffect)
            }
            (consume subscriber)?.receive(completion: completion)
            (consume taskEffect)?.run()
        }
        
        
        private func send(
            isolation actor: isolated some Actor,
            _ value: S.Input
        ) async throws(CancellationError) {
            
            let (subscriber, subscription) = state.withLockUnchecked{
                return ($0.subscriber, $0.upstreamSubscription.subscription)
            }
            guard let subscriber else {
                throw CancellationError()
            }
            // subscriber might call extra `request` or `cancel` but as we don't acquire the lock, it is safe to do so.
            var demand = subscriber.receive(value)
            // subscription can be null, if upstream is already completed
            guard let subscription else {
                return
            }
            defer {
                if demand > .none {
                    subscription.request(demand)
                }
            }
            guard maxTasks != .unlimited else {
                return
            }
            // yield so that other task can access to subscriber for a while.
            await Task.yield()
            demand = state.withLockUnchecked{
                $0.demand.transistion(maxTasks: maxTasks, demand, reduce: true)
            }
        }

        private func waitForUpStream( isolation actor:isolated (any Actor)? = #isolation) async throws {
            try await withTaskCancellationHandler {
                try await withUnsafeThrowingContinuation { coninuation in
                    state.withLockUnchecked{
                        $0.upstreamSubscription.transition(.suspend(coninuation))
                    }?.run()
                }
            } onCancel: {
                state.withLockUnchecked{
                    $0.upstreamSubscription.transition(.cancel)
                }?.run()
            }
        }
        
        func resumeCondition(_ task:Task<Void,Never>) {
            state.withLock{
                $0.condition.transition(.resume(task))
            }?.run()
        }
        
        private func waitForCondition( isolation actor:isolated (any Actor)? = #isolation) async throws {
            try await withUnsafeThrowingContinuation{ continuation in
                state.withLock{
                    $0.condition.transition(.suspend(continuation))
                }?.run()
            }
        }
        
        private func clearCondition() {
            state.withLock{
                $0.condition.transition(.finish)
            }?.run()
        }
        
        @Sendable
        nonisolated func run() async {
            // contention can happen with `resumeCondition(_ :) `
            let token:Void? = try? await waitForCondition()
            if token == nil {
                withUnsafeCurrentTask{
                    $0?.cancel()
                }
            }
            defer {
                clearCondition()
            }
            // contention can happen with `receive(subscription:)
            let success:Void? = try? await waitForUpStream()
            async let job:Void? = state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            await job
            guard success != nil else {
                terminateStream()
                return
            }
            if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, macOS 14.0, watchOS 10.0, visionOS 1.0, *) {
                await withDiscardingTaskGroup(returning: Void.self) { group in
                    await localTask(
                        group: &group
                    )
                }
            } else {
                let barrier = SafetyRegion()
                await { (a:isolated SafetyRegion) in
                    await simuateDiscardingTaskGroup(isolation: a) { actor, group in
                        await localTask(isolation: actor, group: &group)
                    }
                    return ()
                }(barrier)
            }
            // we assume no one is accessing other state
            // except `Subscription.cancel()`
            await send(barrier: SafetyRegion?.none, completion: .finished, cancel: false)

        }
        
    }
    
    
}


extension MultiMapTask.Inner: Subscriber {
    
    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        valueSource.continuation.yield(.success(input))
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Upstream.Failure>) {
        // release upstream subscription
        state.withLockUnchecked{
            $0.upstreamSubscription.transition(.finish)
        }?.run()
        switch completion {
        case .finished:
            break
        case .failure(let failure):
            valueSource.continuation.yield(.failure(failure))
        }
        terminateStream()
    }
    
    typealias Input = Upstream.Output
    
    typealias Failure = Upstream.Failure
    
    func receive(subscription: any Subscription) {
        state.withLockUnchecked {
            $0.upstreamSubscription.transition(.resume(subscription))
        }?.run()
    }

}

extension MultiMapTask.Inner: Subscription {
    
    func request(_ demand: Subscribers.Demand) {
        let (subscription, nextDemand) = state.withLock{
            let subscription = $0.upstreamSubscription.subscription
            let newDemand = if subscription == nil {
                Subscribers.Demand.none
            } else {
                $0.demand.transistion(maxTasks: maxTasks, demand, reduce: false)
            }
            return (subscription, newDemand)
        }
        if let subscription, nextDemand > .none {
            subscription.request(nextDemand)
        }
    }
    
    func cancel() {
        terminateStream()
        let (task, subscription, subscriber) = state.withLockUnchecked{
            let taskEffect = $0.condition.transition(.cancel)
            let subscriptionEffect = $0.upstreamSubscription.transition(.cancel)
            let downstream = $0.subscriber
            $0.subscriber = nil
            return (taskEffect, subscriptionEffect, downstream)
        }
        withExtendedLifetime(subscriber) {
            subscription?.run()
            task?.run()
        }
    }
    
}

extension MultiMapTask.Inner: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var description: String { "MultiMapTask" }
    var playgroundDescription: Any { description }
    
    
}
