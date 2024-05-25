//
//  AsyncSequencePublisher.swift
//  
//
//  Created by pbk on 2022/09/16.
//

import Foundation
import Combine

public extension AsyncSequence {
    
    @inlinable
    var asyncPublisher:AsyncSequencePublisher<Self> {
        .init(base: self)
    }
    
}

public struct AsyncSequencePublisher<Base:AsyncSequence>: Publisher {

    public typealias Output = Base.Element
    public typealias Failure = Error
    
    public var base:Base
    
    @inlinable
    public init(base: Base) {
        self.base = base
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Base.Element == S.Input {
        subscriber.receive(subscription: Inner(base: base, subscriber: subscriber))
    }
    
}

extension AsyncSequencePublisher: Sendable where Base: Sendable, Base.Element: Sendable {}

extension AsyncSequencePublisher {
    
    
    internal struct SubscriptionState<S:Subscriber> where S.Input == Output, S.Failure == Failure {
        
        private let lock: some UnfairStateLock<S?> = createUncheckedStateLock(uncheckedState: S?.none)
        private let demandBuffer:DemandAsyncBuffer
        
        init( subscriber: S, demand:DemandAsyncBuffer) {
            self.demandBuffer = demand
            lock.withLockUnchecked{ $0 = subscriber }
        }
        
        
        func receive(_ value: S.Input) -> Subscribers.Demand? {
            lock.withLockUnchecked{ $0 }?.receive(value)
        }
        
        func receive(completion: Subscribers.Completion<S.Failure>) {
            lock.withLockUnchecked{
                let oldValue = $0
                $0 = nil
                return oldValue
            }?.receive(completion: completion)
        }
        
        func dropSubscriber() {
            // try not to dealloc while holding the lock for safety
            let _ = lock.withLock{
                let oldValue = $0
                $0 = nil
                return oldValue
            }

        }
        
        func startTask(_ source:consuming Base) async {
            var iterator = source.makeAsyncIterator()
            do {
                for await var pending in demandBuffer {
                    while pending > .none {
                        if let value = try await iterator.next() {
                            pending -= 1
                            if let newDemand = receive(value) {
                                pending += newDemand
                            } else {
                                return
                            }
                        } else {
                            receive(completion: .finished)
                            return
                        }
                    }
                }
                receive(completion: .finished)
            } catch {
                receive(completion: .failure(error))
            }
        }

        
    }

    private final class Inner<S:Subscriber>: Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible, Sendable where S.Input == Output, S.Failure == Failure {
        
        var description: String { "AsyncSequence" }
        
        var playgroundDescription: Any { description }
        
        private let task:Task<Void,Never>
        private let demandBuffer = DemandAsyncBuffer()
        
        internal init(base: Base, subscriber:S) {
            let buffer = demandBuffer
            let state = SubscriptionState(subscriber: subscriber, demand: buffer)
            self.task = Task {
                await withTaskCancellationHandler {
                    await state.startTask(base)
                } onCancel: {
                    state.dropSubscriber()
                }
                buffer.close()
            }
        }

        func request(_ demand: Subscribers.Demand) {
            demandBuffer.append(element: demand)
        }
        
        func cancel() {
            task.cancel()
        }
        
        deinit { task.cancel() }
    }
    
    
}
