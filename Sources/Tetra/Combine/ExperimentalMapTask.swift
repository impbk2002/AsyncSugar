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
public struct MultiMapTask<Upstream:Publisher, Output:Sendable>: Publisher where Upstream.Output:Sendable {
    
    public typealias Output = Output
    public typealias Failure = Upstream.Failure

    public let maxTasks:Subscribers.Demand
    public let upstream:Upstream
    public let transform:@Sendable (Upstream.Output) async -> Result<Output,Failure>
    
    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        let processor = Inner(maxTasks: maxTasks, subscriber: subscriber, transform: transform)
        let task = Task(operation: processor.run)
        processor.resumeCondition(task)
        upstream.subscribe(processor)
    }
    
    
    public init(
        maxTasks: Subscribers.Demand = .max(1),
        upstream: Upstream,
        transform: @Sendable @escaping (Upstream.Output) async -> Result<Output, Failure>
    ) {
        precondition(maxTasks != .none, "maxTasks can not be zero")
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = transform
    }
    
}

extension MultiMapTask: Sendable where Upstream: Sendable {}

extension MultiMapTask {

    struct TaskState<S:Subscriber> where S.Failure == Failure, S.Input == Output {
        var demand = PendingDemandState()
        var subscriber:S? = nil
        var upstreamSubscription = SubscriptionContinuation.waiting
        var condition = TaskValueContinuation.waiting
    }
    
    struct Inner<S:Subscriber>: CustomCombineIdentifierConvertible where S.Failure == Failure, S.Input == Output {
        
        private let maxTasks:Subscribers.Demand
        private let valueSource = AsyncStream<Result<Upstream.Output, Failure>>.makeStream()
        private let demandSource = AsyncStream<Subscribers.Demand>.makeStream()
        private let state: some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: TaskState<S>())
        private let transform:@Sendable (Upstream.Output) async -> Result<Output,Failure>

        let combineIdentifier = CombineIdentifier()
        
        init(maxTasks:Subscribers.Demand, subscriber:S, transform: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>) {
            self.maxTasks = maxTasks
            self.transform = transform
            state.withLockUnchecked{
                $0.subscriber = subscriber
            }
        }
        
        private func localTask(
            subscription: any Subscription,
            group: inout some CompatThrowingDiscardingTaskGroup
        ) async throws {
            group.addTask(priority: nil) {
                for await demand in demandSource.stream {
                    let nextDemand = receive(demand: demand)
                    if nextDemand > .none {
                        subscription.request(nextDemand)
                    }
                }
            }
            var iterator = valueSource.stream.makeAsyncIterator()
            while let upstreamValue = await iterator.next() {
                switch upstreamValue {
                case .failure(let failure):
                    send(completion: .failure(failure), cancel: false)
                    throw CancellationError()
                case .success(let success):
                    let flag = group.addTaskUnlessCancelled(priority: nil) {
                        switch await transform(success) {
                        case .failure(let failure):
                            send(completion: .failure(failure), cancel: true)
                            throw CancellationError()
                        case .success(let value):
                            if let demand = send(value) {
                                if demand > .none {
                                    subscription.request(demand)
                                }
                            } else {
                                throw CancellationError()
                            }
                        }
                    }
                    if !flag {
                        break
                    }
                }
            }
        }
        
        private func terminateStream() {
            demandSource.continuation.finish()
            valueSource.continuation.finish()
        }
        
        private func send(completion: Subscribers.Completion<Failure>?, cancel:Bool = false) {
            terminateStream()
            let (subscriber, effect) = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let effect = if cancel {
                    $0.condition.transition(.cancel)
                } else {
                    $0.condition.transition(.finish)
                }
                return (old, effect)
            }
            effect?.run()
            if let completion {
                subscriber?.receive(completion: completion)
            }
        }
        
        private func send(_ value: S.Input) -> Subscribers.Demand? {
            let newDemand = state.withLockUnchecked{
                $0.subscriber
            }?.receive(value)
            guard let newDemand else { return nil }
            
            if maxTasks == .unlimited {
                return newDemand
            }
            return state.withLock{
                $0.demand.transistion(maxTasks: maxTasks, newDemand, reduce: true)
            }
        }
        
        private func receive(demand:Subscribers.Demand) -> Subscribers.Demand {
            if maxTasks == .unlimited {
                return demand
            }
            return state.withLock{
                $0.demand.transistion(maxTasks: maxTasks, demand, reduce: false)
            }
        }

        private func waitForUpStream() async -> (any Subscription)? {
            await withTaskCancellationHandler {
                await withUnsafeContinuation { coninuation in
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
            let subscription = await waitForUpStream()
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            guard let subscription else {
                terminateStream()
                return
            }
            await withTaskCancellationHandler {
                if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, macOS 14.0, watchOS 10.0, visionOS 1.0, *) {
                    try? await withThrowingDiscardingTaskGroup(returning: Void.self) { group in
                        defer { terminateStream() }
                        try await localTask(
                            subscription: subscription,
                            group: &group
                        )
                    }
                } else {
                    try? await withThrowingTaskGroup(of: Void.self, returning: Void.self) { group in
                        defer { terminateStream() }
                        let lock = createCheckedStateLock(checkedState: DiscardingTaskState.waiting)
                        group.addTask {
                            // keep at least one child task alive
                            try await withUnsafeThrowingContinuation{ continuation in
                                lock.withLock{
                                    $0.transition(.suspend(continuation))
                                }?.run()
                            }
                        }
                        var iterator = group.makeAsyncIterator()
                        let stream = AsyncThrowingStream(unfolding: { return try await iterator.next() })
                        async let subTask:() = {
                            for try await _ in stream {
                                
                            }
                        }()
                        do {
                            try await localTask(
                                subscription: subscription,
                                group: &group
                            )
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
                send(completion: .finished)
            } onCancel: {
                subscription.cancel()
                send(completion: nil, cancel: false)
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
        demandSource.continuation.yield(demand)
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
