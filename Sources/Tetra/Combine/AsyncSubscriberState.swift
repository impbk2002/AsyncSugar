//
//  AsyncSubscriberState.swift
//
//
//  Created by 박병관 on 5/31/24.
//

import Foundation
import Combine

struct AsyncSubscriberState<Input, Failure:Error> {
    typealias Continuation = UnsafeContinuation<Result<Input,Failure>?,Never>

    private var subscription = SubscriptionState.awaitingSubscription
    private var pending:[Continuation] = []
    private var pendingDemand = Subscribers.Demand.none
    
    enum Event {
        
        case receive(any Subscription)
        case resume(Input)
        case suspend(Continuation)
        case terminate(Subscribers.Completion<Failure>?)
    }
    
    enum SubscriptionState {
        case awaitingSubscription
        case subscribed(any Subscription)
        case terminal(Failure?)
    }
    
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
    
    enum Effect {
        
        case resumeNil([Continuation])
        case resumeValue(Continuation, Input)
        case resumeFailure([Continuation], Failure)
        case request(any Subscription, Subscribers.Demand)
        case cancelSubscription(any Subscription)
        case cancel([Continuation], (any Subscription)?)
        
        consuming func run() {
            switch consume self {
            case .resumeNil(let array):
                array.forEach{ $0.resume(returning: nil) }
            case .resumeValue(let continuation, let input):
                continuation.resume(returning: .success(input))
            case .request(let subscription, let demand):
                subscription.request(demand)
            case .cancelSubscription(let subscription):
                subscription.cancel()
            case .cancel(let array, let subscription):
                array.forEach{ $0.resume(returning: nil) }
                subscription?.cancel()
            case .resumeFailure(let array, let failure):
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
            return .resumeNil(jobs)
        case .subscribed:
            precondition(!pending.isEmpty,"Received an output without requesting demand")
            let continuation = pending.removeFirst()
            return .resumeValue(continuation, value)
        case .terminal:
            let jobs = pending
            pending.removeAll()
            return .resumeNil(jobs)
        }
    }
    
    private mutating func resume(completion: Subscribers.Completion<Failure>) -> Effect? {
        let jobs = pending
        pending.removeAll()
        switch subscription {
        case .awaitingSubscription, .subscribed:
            if !jobs.isEmpty {
                subscription = .terminal(nil)
                switch completion {
                case .finished:
                    return .resumeNil(jobs)
                case .failure(let failure):
                    return .resumeFailure(jobs, failure)
                }
            } else {
                switch completion {
                case .finished:
                    subscription = .terminal(nil)
                case .failure(let failure):
                    subscription = .terminal(failure)
                }
                return nil
            }
        case .terminal:
            return .resumeNil(jobs)
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
            return .resumeNil([continuation])
        case .terminal(let failure?):
            subscription = .terminal(nil)
            return .resumeFailure([continuation], failure)
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
            return .cancelSubscription(subscription)
        case .terminal:
            return .cancelSubscription(subscription)
        }
    }
}
