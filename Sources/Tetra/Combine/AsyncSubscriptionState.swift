//
//  AsyncSubscriptionState.swift
//
//
//  Created by 박병관 on 6/7/24.
//

import Foundation
import Combine

enum AsyncSubscriptionState {
    
    
    case waiting
    case suspending(UnsafeContinuation<Void,any Error>)
    case cached(any Subscription)
    case cancelled
    case finished
    
    var subscription:(any Subscription)? {
        guard case let .cached(subscription) = self else {
            return nil
        }
        return subscription
    }
    
    
    enum Event {
        
        case suspend(UnsafeContinuation<Void,any Error>)
        case resume(any Subscription)
        case cancel
        case finish
        
    }
    
    enum Effect {
        
        case resume(UnsafeContinuation<Void,any Error>)
        case raise(UnsafeContinuation<Void,any Error>)
        case cancel(any Subscription)
        // ensure deinit is called outside of lock
        case discard(any Subscription)
        
        
        consuming func run() {
            switch self {
            case .resume(let unsafeContinuation):
                unsafeContinuation.resume()
            case .raise(let unsafeContinuation):
                unsafeContinuation.resume(throwing: CancellationError())
            case .cancel(let subscription):
                subscription.cancel()
            case .discard:
                break
            }
        }
        
    }
    
    @usableFromInline
    func shouldMutate(_ event: Event) -> Bool {
        switch self {
        case .waiting:
            return true
        case .suspending(_):
            if case .suspend = event {
                return false
            } else {
                return true
            }
        case .cached(_):
            if case .resume = event {
                return false
            } else {
                return true
            }
        case .cancelled, .finished:
            return false
        }
    }
    
    mutating func transition(_ event:Event) -> sending Effect? {
        switch event {
        case .suspend(let unsafeContinuation):
            return suspend(unsafeContinuation)
        case .resume(let subscription):
            return resume(subscription)
        case .cancel:
            return onCancel()
        case .finish:
            return finish()
        }
    }
    
    
    
    private mutating func onCancel() -> Effect?{
        switch self {
        case .waiting, .cancelled:
            self = .cancelled
            return nil
        case .suspending(let unsafeContinuation):
            self = .cancelled
            return .raise(unsafeContinuation)
        case .cached(let subscription):
            self = .cancelled
            return .cancel(subscription)
        case .finished:
            return nil
        }
    }
    
    private mutating func resume(_ subscription:any Subscription) -> Effect? {
        switch self {
        case .waiting:
            self = .cached(subscription)
            return nil
        case .suspending(let unsafeContinuation):
            self = .cached(subscription)
            return .resume(unsafeContinuation)
        case .cached:
            assertionFailure("Received Subscription more than Once")
            return .cancel(subscription)
        case .cancelled:
            fallthrough
        case .finished:
            return .cancel(subscription)
        }
    }
    
    private mutating func suspend(_ continuation: UnsafeContinuation<Void,any Error>) -> sending Effect? {
        switch self {
        case .waiting:
            self = .suspending(continuation)
            return nil
        case .suspending(let unsafeContinuation):
            self = .suspending(unsafeContinuation)
            assertionFailure("Received Continuation more than Once")
            return .raise(continuation)
        case .cancelled:
            return .raise(continuation)
        case .finished:
            fallthrough
        case .cached:
            return .resume(continuation)
        }
    }
    
    private mutating func finish() -> sending Effect? {
        switch self {
        case .suspending(let unsafeContinuation):
            self = .finished
            return .resume(unsafeContinuation)
        case .cached(let subscription):
            self = .finished
            return .discard(subscription)
        case .waiting:
            self = .finished
            fallthrough
        case .finished:
            fallthrough
        case .cancelled:
            return nil
        }
    }
    
}
