//
//  AsyncSubscriberState.swift
//
//
//  Created by 박병관 on 5/31/24.
//

import Foundation
import Combine

@usableFromInline
struct AsyncSubscriberState<Input, Failure:Error> {
    
    @usableFromInline
    typealias Continuation = UnsafeContinuation<Result<Input,Failure>?,Never>

    private var subscription = SubscriptionState.awaitingSubscription
    private var pending:[Continuation] = []
    private var pendingDemand = Subscribers.Demand.none
    
    @usableFromInline
    enum Event {
        
        case receive(any Subscription)
        case resume(Input)
        case suspend(Continuation)
        case terminate(Subscribers.Completion<Failure>?)
    }
    
    @usableFromInline
    enum SubscriptionState {
        case awaitingSubscription
        case subscribed(any Subscription)
        case terminal(Failure?)
    }
    
    @usableFromInline
    mutating func transition(_ event: consuming Event) -> Effect? {
        switch consume event {
        case .receive(let subscription):
            return receive(subscription)
        case .resume(let input):
            return resume(input)
        case .suspend(let continuation):
            return suspend(continuation)
        case .terminate(let completion):
            if let completion {
                return resume(completion: completion)
            } else {
                return cancel()
            }
        }
    }
    
    @usableFromInline
    enum Effect {
        
        case resumeValue(Continuation, Input)
        case resumeFailure([Continuation], Failure, discard: (any Subscription)?)
        case request(any Subscription, Subscribers.Demand)
        case cancel([Continuation], (any Subscription)?)
        case cancelAndDiscard([Continuation], discard: (any Subscription)?)
        case discard((any Subscription)?)
        
        @usableFromInline
        consuming func run() {
            switch consume self {
            case .discard:
                break
            case .resumeValue(let continuation, let input):
                nonisolated(unsafe)
                let value = Result<Input,Failure>.success(consume input)
                continuation.resume(returning: Suppress(value: value).value)
            case .request(let subscription, let demand):
                subscription.request(demand)
            case .cancelAndDiscard(let array, discard: _):
                array.forEach{ $0.resume(returning: nil) }
            case .cancel(let array, let subscription):
                array.forEach{ $0.resume(returning: nil) }
                subscription?.cancel()
            case .resumeFailure(let array, let failure, _):
                array[0].resume(returning: .failure(failure))
                array.dropFirst().forEach{ $0.resume(returning: nil) }
            }
        }
    }
    
    private mutating func resume(_ value:Input) -> Effect? {
        switch subscription {
        case .awaitingSubscription:
            assertionFailure("Received an output without subscription")
            let jobs = pending
            pending.removeAll()
            return .cancel(jobs, nil)
        case .subscribed:
            precondition(!pending.isEmpty,"Received an output without requesting demand")
            let continuation = pending.removeFirst()
            return .resumeValue(continuation, value)
        case .terminal:
            let jobs = pending
            pending.removeAll()
            return .cancel(jobs, nil)
        }
    }
    
    private mutating func resume(completion: Subscribers.Completion<Failure>) -> Effect? {
        let jobs = pending
        pending.removeAll()
        let oldSubscription = if case let .subscribed(token) = subscription {
            token
        } else {
            nil as (any Subscription)?
        }
        switch subscription {
        case .awaitingSubscription, .subscribed:
            if !jobs.isEmpty {
                subscription = .terminal(nil)
                switch completion {
                case .finished:
                    return .cancelAndDiscard(jobs, discard: oldSubscription)
                case .failure(let failure):
                    return .resumeFailure(jobs, failure, discard: oldSubscription)
                }
            } else {
                switch completion {
                case .finished:
                    subscription = .terminal(nil)
                case .failure(let failure):
                    subscription = .terminal(failure)
                }
                return .discard(oldSubscription)
            }
        case .terminal:
            return .cancel(jobs, nil)
        }
    }
    
    private mutating func cancel() -> Effect? {
        let oldState = subscription
        let jobs = pending
        subscription = .terminal(nil)
        pending.removeAll()
        var token:(any Subscription)? = nil
        if case let .subscribed(wrapped) = oldState {
            token = wrapped
        }
        return .cancel(jobs, token)
    }
    
    private mutating func suspend(_ continuation:UnsafeContinuation<Result<Input,Failure>?,Never>) ->  Effect? {
        switch subscription {
        case .awaitingSubscription:
            pending.append(continuation)
            pendingDemand += 1
            return nil
        case .subscribed(let subscription):
            pending.append(continuation)
            return .request(subscription, .max(1))
        case .terminal(.none):
            return .cancel([continuation], nil)
        case .terminal(let failure?):
            subscription = .terminal(nil)
            return .resumeFailure([continuation], failure, discard: nil)
        }
    }
    
    private mutating func receive(_ subscription: any Subscription) -> Effect? {
        switch self.subscription {
        case .awaitingSubscription:
            let demand = pendingDemand
            pendingDemand = .none
            self.subscription = .subscribed(subscription)
            if demand > .none {
                return .request(subscription, demand)
            } else {
                return nil
            }
        case .subscribed:
            assertionFailure("Received subscription more than Once")
            return .cancel([], subscription)
        case .terminal:
            return .cancel([], subscription)
        }
    }
}
