//
//  File.swift
//  
//
//  Created by 박병관 on 5/15/24.
//

import Foundation
import Combine


internal protocol CompatThrowingDiscardingTaskGroup {
    
    var isCancelled:Bool { get }
    var isEmpty:Bool { get }
    func cancelAll()
    mutating func addTaskUnlessCancelled(
        priority: TaskPriority?,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Bool
    mutating func addTask(
        priority: TaskPriority?,
        operation: @escaping @Sendable () async throws -> Void
    )

}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, macCatalyst 17.0, visionOS 1.0, *)
extension ThrowingDiscardingTaskGroup: CompatThrowingDiscardingTaskGroup {

}

extension ThrowingTaskGroup: CompatThrowingDiscardingTaskGroup where ChildTaskResult == Void {

}

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
        subscriber
            .receive(
                subscription: Inner(
                    maxTasks: maxTasks,
                    upstream: upstream, 
                    subscriber: subscriber,
                    transform: transform
                )
            )
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
    
    internal struct DelegateState<S:Subscriber> where S.Input == Output, S.Failure == Failure {
        
        let demandState: some UnfairStateLock<PendingDemandState> = createCheckedStateLock(checkedState: PendingDemandState(taskCount: 0, pendingDemand: .none))
        let subscriberState: some UnfairStateLock<S?> = createUncheckedStateLock(uncheckedState: .none)
        let buffer:DemandAsyncBuffer
        let maxTasks:Subscribers.Demand
        let transform: @Sendable (Upstream.Output) async -> Result<Output,Failure>
        
        init(
            buffer: DemandAsyncBuffer,
            maxTasks: Subscribers.Demand,
            subscriber:S,
            transform: @Sendable @escaping (Upstream.Output) async -> Result<Output, Failure>
        ) {
            self.subscriberState.withLockUnchecked{ $0 = subscriber }
            self.buffer = buffer
            self.maxTasks = maxTasks
            self.transform = transform
        }
        
        struct PendingDemandState {
            var taskCount:Int
            var pendingDemand:Subscribers.Demand
        }
        
        func processDemand(
            demand:Subscribers.Demand,
            subscription: any Subscription,
            reduce:Bool = false
        ){
            if maxTasks == .unlimited {
                if demand > .none {
                    subscription.request(demand)
                }
            } else {
                let newDemand = demandState.withLock{
                    if reduce {
                        $0.taskCount -= 1
                    }
                    $0.pendingDemand += demand
                    let availableSpace = maxTasks - $0.taskCount
                    if $0.pendingDemand >= availableSpace {
                        $0.pendingDemand -= availableSpace
                        if let maxCount = availableSpace.max {
                            $0.taskCount += maxCount
                        } else {
                            fatalError("availableSpace can not be unlimited while limit is bounded")
                        }
                        return availableSpace
                    } else {
                        let snapShot = $0.pendingDemand
                        if let count = snapShot.max {
                            $0.taskCount += count
                            $0.pendingDemand = .none
                        } else {
                            // pendingDemand is smaller than availableSpace and limit is bounded and pendingDemand is infinite
                            fatalError("pendingDemand can not be unlimited while limit is bounded")
                        }
                        return snapShot
                    }
                }
                if newDemand > .none {
                    subscription.request(newDemand)
                }
            }
        }
        
        func dropSubscriber() {
            subscriberState.withLock{ $0 = nil }
        }
        
        func receiveValue(_ value:Output) -> Subscribers.Demand? {
            subscriberState.withLockUnchecked{ $0 }?.receive(value)
        }
        
        func receiveComplete(_ completion:Subscribers.Completion<Failure>) {
            subscriberState.withLockUnchecked{
                let old = $0
                $0 = nil
                return old
            }?.receive(completion: completion)
        }
        
        func localTask(
            subscription: any Subscription,
            group: inout some CompatThrowingDiscardingTaskGroup,
            stream: some NonThrowingAsyncSequence<Result<Upstream.Output, Failure>>
        ) async {
            group.addTask(priority: nil) {
                for await demand in buffer {
                    processDemand(demand: demand, subscription: subscription)
                }
            }
            var iterator = stream.makeAsyncIterator()
            while let upstreamValue = await iterator.next() {
                switch upstreamValue {
                case .failure(let failure):
                    receiveComplete(.failure(failure))
                    break
                case .success(let success):
                    let flag = group.addTaskUnlessCancelled(priority: nil) {
                        switch await transform(success) {
                        case .failure(let failure):
                            receiveComplete(.failure(failure))
                        case .success(let value):
                            if let demand = receiveValue(value) {
                                processDemand(demand: demand, subscription: subscription, reduce: true)
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
            receiveComplete(.finished)
            buffer.close()
        }
        
        static func makeStream(
            upstream:Upstream,
            receiveSubscription: @escaping (any Subscription) -> Void,
            onCancel: @escaping @Sendable () -> Void
        ) -> AsyncStream<Result<Upstream.Output,Failure>> {
            return .init { continuation in
                continuation.onTermination = { _ in
                    onCancel()
                }
                upstream.subscribe(
                    AnySubscriber(
                        receiveSubscription: receiveSubscription,
                        receiveValue: {
                            continuation.yield(.success($0))
                            return .none
                        },
                        receiveCompletion: {
                            switch $0 {
                            case .finished:
                                break
                            case .failure(let error):
                                continuation.yield(.failure(error))
                            }
                            continuation.finish()
                        }
                    )
                )
            }
        }
    }
    
    private final class Inner:Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible  {
        
        var description: String { "MultiMapTask" }
        
        var playgroundDescription: Any { description }
        private let task:Task<Void,Never>
        private let demander:DemandAsyncBuffer

        // TODO: Replace with Delegating StateHolder
        fileprivate init<S:Subscriber>(
            maxTasks:Subscribers.Demand,
            upstream:Upstream,
            subscriber:S,
            transform: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>
        ) where S.Input == Output, S.Failure == Failure {
            precondition(maxTasks != .none, "maxTasks can not be zero")
            let buffer = DemandAsyncBuffer()
            demander = buffer
            let state = DelegateState(buffer: buffer, maxTasks: maxTasks, subscriber: subscriber, transform: transform)
            task = Task {
                let subscriptionLock = createCheckedStateLock(checkedState: SubscriptionContinuation.waiting)
                let stream = DelegateState<S>.makeStream(upstream: upstream, receiveSubscription: subscriptionLock.received, onCancel: { buffer.close() })
                guard let subscription = await subscriptionLock.consumeSubscription()
                else { return }
                await withTaskCancellationHandler {
                    if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, macOS 14.0, watchOS 10.0, visionOS 1.0, *) {
                        try? await withThrowingDiscardingTaskGroup(returning: Void.self) { group in
                            await state.localTask(subscription: subscription, group: &group, stream: stream)
                        }
                    } else {
                        await withThrowingTaskGroup(of: Void.self, returning: Void.self) { group in
                            let gIterator = group.makeAsyncIterator()
                            async let subTask:() = {
                                var iterator = gIterator
                                while let _ = try? await iterator.next() {
                                    
                                }
                            }()
                            await state.localTask(subscription: subscription, group: &group, stream: stream)
                            await subTask
                        }
                    }

                } onCancel: {
                    subscription.cancel()
                    state.dropSubscriber()
                }
            }
        }
        
        func cancel() {
            task.cancel()
        }
        
        func request(_ demand: Subscribers.Demand) {
            demander.append(element: demand)
        }
        
        deinit { task.cancel() }
    }
    
    
}
