//
//  File.swift
//  
//
//  Created by 박병관 on 6/3/24.
//

import Foundation
@preconcurrency import Combine

@usableFromInline
internal struct AsyncSubscriber<P:Publisher>: Sendable, Subscriber, Cancellable {
    
    
    public typealias Input = P.Output
    public typealias Failure = P.Failure
    
    private let lock:some UnfairStateLock<AsyncSubscriberState<P.Output,P.Failure>> = createUncheckedStateLock(uncheckedState: .init())

    
    public let combineIdentifier = CombineIdentifier()
    
    @usableFromInline 
    func receive(_ input: Input) -> Subscribers.Demand {
        lock.withLockUnchecked{
            $0.transition(.resume(input))
        }?.run()
        
        return .none
    }
    
    @usableFromInline
    func receive(completion: Subscribers.Completion<Failure>) {
        lock.withLockUnchecked{
            $0.transition(.terminate(completion))
        }?.run()
    }
    
    @usableFromInline 
    func receive(subscription: Subscription) {
        lock.withLockUnchecked{
            $0.transition(.receive(subscription))
        }?.run()
    }
    
    
    @usableFromInline 
    func cancel() {
        lock.withLockUnchecked{
            $0.transition(.terminate(nil))
        }?.run()
    }
    
    @usableFromInline
    func next() async -> Result<Input,Failure>? {
        return await withUnsafeContinuation { continuation in
            lock.withLockUnchecked{
                $0.transition(.suspend(continuation))
            }?.run()
         }
    }
    
    @usableFromInline
    init() {
        
    }
    
}
