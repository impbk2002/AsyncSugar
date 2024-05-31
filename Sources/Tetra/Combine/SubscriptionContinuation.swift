//
//  SubscriptionContinuation.swift
//  
//
//  Created by pbk on 2023/01/29.
//

import Foundation
@preconcurrency import Combine

@usableFromInline
internal enum SubscriptionContinuation {
    
    case waiting
    case cached(any Subscription)
    case suspending(UnsafeContinuation<Subscription?,Never>)
    case finished
    
    enum Event {
        case resume(any Subscription)
        case suspend(UnsafeContinuation<Subscription?, Never>)
        case cancel
    }
    
    enum Effect {
        case drop(any Subscription)
        case resume(UnsafeContinuation<Subscription?,Never>, any Subscription)
        case cancel(UnsafeContinuation<Subscription?,Never>)
        
        consuming func run() {
            switch consume self {
            case .drop(let subscription):
                subscription.cancel()
            case .resume(let unsafeContinuation, let subscription):
                unsafeContinuation.resume(returning: subscription)
            case .cancel(let unsafeContinuation):
                unsafeContinuation.resume(returning: nil)
            }
        }
    }
    
    mutating func transition(_ event:consuming Event) -> Effect? {
        switch consume event {
        case .resume(let subscription):
            return resume(subscription)
        case .suspend(let unsafeContinuation):
            return suspend(unsafeContinuation)
        case .cancel:
            return cancel()
        }
    }
    

    private mutating func resume(_ subscription: any Subscription) -> Effect? {
        switch self {
        case .waiting:
            self = .cached(subscription)
            return nil
        case .cached(let oldValue):
            self = .cached(subscription)
            assertionFailure("received subscption more than once")
            return .drop(oldValue)
        case .suspending(let unsafeContinuation):
            self = .finished
            return .resume(unsafeContinuation, subscription)
        case .finished:
            return nil
        }
    }
    
    private mutating func suspend(_ continuation: UnsafeContinuation<Subscription?, Never>) -> Effect? {
        switch self {
        case .waiting:
            self = .suspending(continuation)
            return nil
        case .cached(let subscription):
            self = .finished
            return .resume(continuation, subscription)
        case .suspending(let oldValue):
            self = .suspending(continuation)
            assertionFailure("received continuation more than once")

            return .cancel(oldValue)
        case .finished:
            
            return .cancel(continuation)
        }
    }
    
    private mutating func cancel() -> Effect? {
        switch self {
        case .waiting:
            self = .finished
            return nil
        case .cached(let subscription):
            self = .finished
            return .drop(subscription)
        case .suspending(let unsafeContinuation):
            self = .finished
            return .cancel(unsafeContinuation)
        case .finished:
            return nil
        }
    }
    
}
