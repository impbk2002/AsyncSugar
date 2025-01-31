//
//  AsyncSequencePublisher.swift
//  
//
//  Created by pbk on 2022/09/16.
//

import Foundation
@preconcurrency import Combine
public import BackPortAsyncSequence
internal import CriticalSection
import Namespace

public extension TetraExtension where Base: AsyncSequence {
    
    @available(*, deprecated, renamed: "toPublisher()", message: "use toPublisher() which provides task priority and isolation")
    var publisher:some Publisher<Base.Element, any Error> {
        toPublisher()
    }
    
    
    @_disfavoredOverload
    @inlinable
    func toPublisher(
        barrier: (any Actor)? = #isolation,
        priority: TaskPriority? = nil
    ) -> some Publisher<Base.Element, any Error> {
        AsyncSequencePublisher(
            base: LegacyTypedAsyncSequence(base: base),
            barrier: barrier,
            priority: priority
        )
    }
    
}

public extension TetraExtension where Base: TypedAsyncSequence, Base.AsyncIterator: TypedAsyncIteratorProtocol {
    
    @inlinable
    func toPublisher<Element,Failure:Error>(
        barrier: (any Actor)? = #isolation,
        priority: TaskPriority? = nil
    ) -> some Publisher<Element, Failure> where Element == Base.Element, Failure == Base.AsyncIterator.Err {
        AsyncSequencePublisher(
            base: base,
            barrier: barrier,
            priority: priority
        )
    }
    
}


public struct AsyncSequencePublisher<Base: AsyncSequence>: Publisher where Base.AsyncIterator: TypedAsyncIteratorProtocol {
    public typealias Output = Base.AsyncIterator.Element
    
    public typealias Failure = Base.AsyncIterator.Err
    
    public var base:Base
    public var barrier: (any Actor)? = nil
    public var priority: TaskPriority? = nil
    
    @inlinable
    public init(
        base: Base,
        barrier: (any Actor)? = nil,
        priority: TaskPriority? = nil
    ) {
        self.base = base
        self.barrier = barrier
        self.priority = priority
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Base.AsyncIterator.Element == S.Input {
        let processor = Inner(subscriber: subscriber)
        let unsafe = Suppress(value: base.makeAsyncIterator())
        let task = Task(priority: priority) { [capture = consume unsafe, barrier] in
            var iter = capture.value
            await processor.run(barrier, &iter)
        }
        processor.resumeCondition(task)
    }
    
}


extension AsyncSequencePublisher: Sendable where Base: Sendable, Base.Element: Sendable {}


extension AsyncSequencePublisher {
    
    internal struct TaskState<S:Subscriber> where S.Input == Output, S.Failure == Failure {
        
        var subscriber:S? = nil
        var condition = TaskValueContinuation.waiting
        var demand = Subscribers.Demand.none
        var continuation:UnsafeContinuation<Subscribers.Demand?,Never>? = nil
        var terminated = false
        
    }
    
    internal struct Inner<S:Subscriber>: Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible, Sendable where S.Input == Output, S.Failure == Failure {
        
        var description: String { "AsyncSequence" }
        
        var playgroundDescription: Any { description }
        let combineIdentifier = CombineIdentifier()
        private let state:some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: .init())
        
        init(subscriber:S) {
            state.withLockUnchecked{
                $0.subscriber = subscriber
            }
        }
        
        func cancel() {
            send(completion: nil)
        }
        
        func request(_ demand: Subscribers.Demand) {
            let tuple:(UnsafeContinuation<Subscribers.Demand?,Never>, Subscribers.Demand)? = state.withLock{
                $0.demand += demand
                let old = $0.continuation
                $0.continuation = nil
                if let old, $0.demand > .none {
                    let newDemand = $0.demand
                    $0.demand = .none
                    return (old, newDemand)
                } else {
                    return .none
                }
            }
            guard let (token, newDemand) = tuple else { return }
            token.resume(returning: newDemand)
        }
        
        private func send(_ value:S.Input) -> Subscribers.Demand? {
            state.withLockUnchecked{ $0.subscriber }?.receive(value)
        }
        
        private func send(completion: Subscribers.Completion<S.Failure>?) {
            let (subscriber, effect, token) = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                $0.terminated = true
                let effect = $0.condition.transition(completion == nil ? .cancel : .finish)
                let token = $0.continuation
                $0.continuation = nil
                return (old, effect, token)
            }
            if let completion {
                subscriber?.receive(completion: completion)
            }
            token?.resume(returning: nil)
            effect?.run()
        }
        
        func resumeCondition(_ task:Task<Void,Never>) {
            state.withLock{
                $0.condition.transition(.resume(task))
            }?.run()
        }
        
        private func waitForCondition( _ actor: isolated (any Actor)? = #isolation) async throws {
            try await withUnsafeThrowingContinuation{ continuation in
                state.withLock{
                    $0.condition.transition(.suspend(continuation))
                }?.run()
            }
        }
        
        private func nextDemand( _ actor: isolated (any Actor)? = #isolation) async -> Subscribers.Demand? {
            await withUnsafeContinuation{ continuation in
                let demand:Subscribers.Demand? = state.withLock{
                    if $0.demand > .none {
                        let newDemand = $0.demand
                        $0.demand = .none
                        return newDemand
                    } else if $0.continuation == nil {
                        $0.continuation = continuation
                        return Subscribers.Demand.none
                    } else {
                        assertionFailure("received \(#function) twice at the same time")
                        return nil
                    }
                    
                }
                if let demand, demand > .none {
                    continuation.resume(returning: demand)
                }
                if demand == nil {
                    continuation.resume(returning: nil)
                }
                
            }
        }

        
        func run(
            _ actor: isolated (any Actor)? = #isolation,
            _ iterator: inout Base.AsyncIterator
        ) async {
            let token:Void? = try? await waitForCondition()
            if token == nil {
                send(completion: nil)
            }
            
            async let job:Void = { (actor:isolated (any Actor)?) in
                state.withLockUnchecked{
                    $0.subscriber
                }?.receive(subscription: self)
            }(actor)
            await job
            do {
                while var pending = await nextDemand() {
                    while pending > .none {
                        pending -= 1
                        guard let value = try await iterator.next(isolation: actor)
                        else {
                            send(completion: .finished)
                            return
                        }
                        guard let newDemand = send(value) else {
                            return
                        }
                        pending += newDemand
                    }
                }
            } catch {
                send(completion: .failure(error))
            }
        }
        
    }
    
}
