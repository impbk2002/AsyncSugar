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
internal struct MultiMapTask<Upstream:Publisher, Output:Sendable>: Publisher where Upstream.Output:Sendable {
    
    public typealias Output = Output
    public typealias Failure = Upstream.Failure

    public let maxTasks:Subscribers.Demand
    public let upstream:Upstream
    public let transform:@Sendable (Upstream.Output) async -> Result<Output,Failure>
    
    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        let processor = Inner(maxTasks: maxTasks, subscriber: subscriber, transform: transform)
        let task = Task {
            await processor.run()
        }
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
        var demand = PendingDemandState(taskCount: 0, pendingDemand: .none)
        var subscriber:S? = nil
        var upstreamSubscription = SubscriptionContinuation.waiting
        var condition = TaskValueContinuation.waiting
    }
    
    struct Inner<S:Subscriber>: CustomCombineIdentifierConvertible where S.Failure == Failure, S.Input == Output {
        
        let maxTasks:Subscribers.Demand
        let valueSource = AsyncStream<Result<Upstream.Output, Failure>>.makeStream()
        let demandSource = AsyncStream<Subscribers.Demand>.makeStream()
        let state: some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: TaskState<S>())
        let transform:@Sendable (Upstream.Output) async -> Result<Output,Failure>

        let combineIdentifier = CombineIdentifier()
        
        init(maxTasks:Subscribers.Demand, subscriber:S, transform: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>) {
            self.maxTasks = maxTasks
            self.transform = transform
            state.withLockUnchecked{
                $0.subscriber = subscriber
            }
        }
        
        func localTask(
            subscription: any Subscription,
            group: inout some CompatThrowingDiscardingTaskGroup
        ) async {
            group.addTask(priority: nil) {
                for await demand in demandSource.stream {
                    let nextDemand = receive(demand: demand)
                    subscription.request(nextDemand)
                }
            }
            var iterator = valueSource.stream.makeAsyncIterator()
            while let upstreamValue = await iterator.next() {
                switch upstreamValue {
                case .failure(let failure):
                    send(completion: .failure(failure))
                    break
                case .success(let success):
                    let flag = group.addTaskUnlessCancelled(priority: nil) {
                        switch await transform(success) {
                        case .failure(let failure):
                            send(completion: .failure(failure))
                            throw CancellationError()
                        case .success(let value):
                            if let demand = send(value) {
                                subscription.request(demand)
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
        
        func terminateStream() {
            demandSource.continuation.finish()
            valueSource.continuation.finish()
        }
        
        func send(completion: Subscribers.Completion<Failure>?) {
            let subscriber = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                return old
            }
            if let completion {
                subscriber?.receive(completion: completion)
            }
        }
        
        func send(_ value: S.Input) -> Subscribers.Demand? {
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
        
        func receive(demand:Subscribers.Demand) -> Subscribers.Demand {
            if maxTasks == .unlimited {
                return demand
            }
            return state.withLock{
                $0.demand.transistion(maxTasks: maxTasks, demand, reduce: false)
            }
        }

        func waitForUpStream() async -> (any Subscription)? {
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
        
        func waitForCondition() async throws {
            try await withUnsafeThrowingContinuation{ continuation in
                state.withLock{
                    $0.condition.transition(.suspend(continuation))
                }?.run()
            }
        }
        
        func clearCondition() {
            state.withLock{
                $0.condition.transition(.finish)
            }?.run()
        }
        
        func run() async {
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
                        await localTask(
                            subscription: subscription,
                            group: &group
                        )
                    }
                } else {
                    try? await withThrowingTaskGroup(of: Void.self, returning: Void.self) { group in
                        defer { terminateStream() }
                        var iterator = group.makeAsyncIterator()
                        let stream = AsyncThrowingStream(unfolding: { try await iterator.next() })
                        async let subTask:() = {
                            for try await _ in stream {
                                
                            }
                        }()
                        await localTask(
                            subscription: subscription,
                            group: &group
                        )
                        try await subTask
                    }
                }
                send(completion: .finished)
            } onCancel: {
                subscription.cancel()
                send(completion: nil)
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
