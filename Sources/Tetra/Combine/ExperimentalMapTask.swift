//
//  File.swift
//  
//
//  Created by 박병관 on 5/15/24.
//

import Foundation
@preconcurrency import Combine




/**
    Manage Multiple Child Task. provides similair behavior of `flatMap`'s `maxPublisher`
    
    precondition `maxTasks` must be none zero value
 */
@_spi(Experimental)
public struct MultiMapTask<Upstream:Publisher, Output>: Publisher where Upstream.Output:Sendable {
    
    public typealias Output = Output
    public typealias Failure = Upstream.Failure

    public let maxTasks:Subscribers.Demand
    public let upstream:Upstream
    public let transform: @isolated(any) @Sendable (Upstream.Output) async throws(Failure) -> sending Output
    public let taskExecutor: (any Executor)?
    
    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        let processor = Inner(maxTasks: maxTasks, subscriber: subscriber, transform: transform)
        let task = if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *), let executor = taskExecutor as? (any TaskExecutor) {
            Task(executorPreference: executor, operation: processor.run)
        } else {
            Task(operation: processor.run)
        }
        processor.resumeCondition(task)
        upstream.subscribe(processor)
    }
    
    
    public init(
        maxTasks: Subscribers.Demand = .max(1),
        upstream: Upstream,
        transform: @Sendable @escaping @isolated(any) (Upstream.Output) async throws(Failure) -> Output
    ) {
        precondition(maxTasks != .none, "maxTasks can not be zero")
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = transform
        self.taskExecutor = nil
    }
    
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public init(
        maxTasks: Subscribers.Demand = .max(1),
        executor:(any TaskExecutor)? = nil,
        upstream: Upstream,
        transform: @Sendable @escaping @isolated(any) (Upstream.Output) async throws(Failure) -> Output
    ) {
        precondition(maxTasks != .none, "maxTasks can not be zero")
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = transform
        self.taskExecutor = executor
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
        private let state: some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: TaskState<S>())
        private let transform:@Sendable (Upstream.Output) async throws(Failure) -> Output

        let combineIdentifier = CombineIdentifier()
        
        init(
            maxTasks:Subscribers.Demand,
            subscriber:S,
            transform: @escaping @Sendable (Upstream.Output) async throws(Failure) -> Output
        ) {
            self.maxTasks = maxTasks
            self.transform = transform
            state.withLockUnchecked{
                $0.subscriber = subscriber
            }
        }
        
        internal func localTask(
            isolation actor: isolated (any Actor)? = #isolation,
            group: inout some CompatThrowingDiscardingTaskGroup
        ) async throws {
            for await upstreamValue in valueSource.stream {
                switch upstreamValue {
                case .failure(let failure):
                    send(completion: .failure(failure), cancel: false)
                    throw CancellationError()
                case .success(let success):
                    let flag = group.addTaskUnlessCancelled(priority: nil) {
                        let result = await wrapToResult(success, transform)
                        switch result {
                        case .failure(let error):
                            send(completion: .failure(error), cancel: true)
                            throw CancellationError()
                        case .success(let success):
                            try send(success)
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
        
        private func send(completion: Subscribers.Completion<Failure>?, cancel:Bool = false) {
            terminateStream()
            let (subscriber, effect) = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let effect = if cancel {
                    $0.upstreamSubscription.transition(.cancel)
                } else {
                    $0.upstreamSubscription.transition(.finish)
                }
                return (old, effect)
            }
            effect?.run()
            if let completion {
                subscriber?.receive(completion: completion)
            }
        }
        
        private func send(_ value: S.Input) throws {
            let (subscriber, subscription) = state.withLockUnchecked{
                
                return ($0.subscriber, $0.upstreamSubscription.subscription)
            }
            guard let subscriber, let subscription else {
                throw CancellationError()
            }
            var demand = subscriber.receive(value)
            guard maxTasks != .unlimited else {
                if demand > .none {
                    subscription.request(demand)
                }
                return
            }
            demand = state.withLockUnchecked{
                $0.demand.transistion(maxTasks: maxTasks, demand, reduce: true)
            }
            if demand > .none {
                subscription.request(demand)
            }
        }

        private func waitForUpStream() async throws {
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
        
        private func waitForCondition() async throws {
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
            let token:Void? = try? await waitForCondition()
            if token == nil {
                withUnsafeCurrentTask{
                    $0?.cancel()
                }
            }
            defer {
                clearCondition()
            }
            let success:Void? = try? await waitForUpStream()
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            guard success != nil else {
                terminateStream()
                return
            }
            await withTaskCancellationHandler {
                if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, macOS 14.0, watchOS 10.0, visionOS 1.0, *) {
                    try? await withThrowingDiscardingTaskGroup(returning: Void.self) { group in
                        defer { terminateStream() }
                        try await localTask(
                            group: &group
                        )
                    }
                } else {
                    try? await wrapForBackDeploy(isolation: SafetyRegion())
                }
                send(completion: .finished)
            } onCancel: {
                send(completion: nil, cancel: true)
            }
        }
        
        func wrapForBackDeploy(
            isolation actor: isolated (some Actor)
        ) async throws {
            try await withThrowingTaskGroup(of: Void.self) {
                defer { terminateStream() }
                try await $0.simulateDiscarding(isolation: actor) { isolation, group in
                    try await localTask(isolation: isolation, group: &group)
                }
            }
        }
        
    }
    
    
}


extension MultiMapTask.Inner: Subscriber {
    
    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        valueSource.continuation.yield(.success(input))
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Upstream.Failure>) {
        switch completion {
        case .finished:
            break
        case .failure(let failure):
            valueSource.continuation.yield(.failure(failure))
        }
        valueSource.continuation.finish()
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
            let demand = $0.demand.transistion(maxTasks: maxTasks, demand, reduce: false)
            return (subscription, demand)
        }
        if let subscription, nextDemand > .none {
            subscription.request(nextDemand)
        }
    }
    
    func cancel() {
        state.withLock{
            $0.condition.transition(.cancel)
        }?.run()
    }
    
}

extension MultiMapTask.Inner: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var description: String { "MultiMapTask" }
    var playgroundDescription: Any { description }
    
    
}
