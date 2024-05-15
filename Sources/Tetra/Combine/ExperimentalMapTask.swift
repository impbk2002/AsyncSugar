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
 */
struct MultiMapTask<Upstream:Publisher, Output:Sendable>: Publisher where Upstream.Output:Sendable {
    
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
}

extension MultiMapTask {
    
    private final class Inner<S:Subscriber>:Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible where S.Input == Output, S.Failure == Failure {
        
        var description: String { "MultiMapTask" }
        
        var playgroundDescription: Any { description }
        typealias Stream = AsyncStream<Result<Upstream.Output,S.Failure>>
        private let task:Task<Void,Never>
        private let demander:DemandAsyncBuffer
        
        struct PendingDemandState {
            var taskCount:Int
            var pendingDemand:Subscribers.Demand
        }
        
        // TODO: Replace with Delegating StateHolder
        fileprivate init(
            maxTasks:Subscribers.Demand,
            upstream:Upstream,
            subscriber:S,
            transform: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>
        ) {
            precondition(maxTasks != .none, "maxTasks can not be zero")
            let buffer = DemandAsyncBuffer()
            demander = buffer
            let lock = createUncheckedStateLock(uncheckedState: S?.some(subscriber))
            task = Task {
                let subscriptionLock = createCheckedStateLock(checkedState: SubscriptionContinuation.waiting)
                let demandState = createCheckedStateLock(checkedState: PendingDemandState(taskCount: 0, pendingDemand: .none))
                let stream = Self.makeStream(upstream: upstream, receiveSubscription: subscriptionLock.received, onCancel: { buffer.close() })
                guard let subscription = await subscriptionLock.consumeSubscription()
                else { return }
                func localTask(group: inout some CompatThrowingDiscardingTaskGroup) async {
                    group.addTask(priority: nil) {
                        for await demand in buffer {
                            Self.processDemand(maxTasks: maxTasks, demand: demand, subscription: subscription, state: demandState)
                        }
                    }
                    for await upstreamValue in stream {
                        switch upstreamValue {
                        case .failure(let failure):
                            lock.withLockUnchecked{
                                let old = $0
                                $0 = nil
                                return old
                            }?.receive(completion: .failure(failure))
                            break
                        case .success(let success):
                            let flag = group.addTaskUnlessCancelled(priority: nil) { [success] in
                                switch await transform(success) {
                                case .failure(let failure):
                                    lock.withLockUnchecked{
                                        let old = $0
                                        $0 = nil
                                        return old
                                    }?.receive(completion: .failure(failure))
                                    throw CancellationError()
                                case .success(let value):
                                    if let subscriber = lock.withLockUnchecked({ $0 }) {
                                        let newDemand = subscriber.receive(value)
                                        Self.processDemand(maxTasks: maxTasks, demand: newDemand, subscription: subscription, state: demandState, reduce: true)
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
                await withTaskCancellationHandler {
                    if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, macOS 14.0, watchOS 10.0, visionOS 1.0, *) {
                        try? await withThrowingDiscardingTaskGroup(returning: Void.self) { group in
                            await localTask(group: &group)
                        }
                    } else {
                        await withThrowingTaskGroup(of: Void.self, returning: Void.self) { group in
                            let gIterator = group.makeAsyncIterator()
                            async let subTask:() = {
                                var iterator = gIterator
                                while let _ = try? await iterator.next() {
                                    
                                }
                            }()
                            await localTask(group: &group)
                            await subTask
                        }
                    }

                } onCancel: {
                    subscription.cancel()
                    lock.withLock{ $0 = nil }
                }
                lock.withLockUnchecked{
                    let oldValue = $0
                    $0 = nil
                    return oldValue
                }?.receive(completion: .finished)
                buffer.close()
            }
        }
        
        func cancel() {
            task.cancel()
        }
        
        func request(_ demand: Subscribers.Demand) {
            demander.append(element: demand)
        }
        
        deinit { task.cancel() }
        
        static func makeStream(
            upstream:Upstream,
            receiveSubscription: @escaping (any Subscription) -> Void,
            onCancel: @escaping @Sendable () -> Void
        ) -> Stream {
            return Stream { continuation in
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
        
        static func processDemand(
            maxTasks: Subscribers.Demand,
            demand:Subscribers.Demand,
            subscription: any Subscription,
            state: some UnfairStateLock<PendingDemandState>,
            reduce:Bool = false
        ) {
            if maxTasks == .unlimited {
                if demand > .none {
                    subscription.request(demand)
                }
            } else {
                let newDemand = state.withLock{
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
    }
    
    
}
