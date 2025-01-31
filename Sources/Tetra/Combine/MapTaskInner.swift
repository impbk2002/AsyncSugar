//
//  MapTaskInner.swift
//  
//
//  Created by 박병관 on 6/28/24.
//
import Combine

struct MapTaskInner<S:Subscriber>: Subscription, Subscriber, CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var description: String
    
    var playgroundDescription: Any { description }
    
    var downstream:S
    var upstream:Subscription? = nil
    var combineIdentifier: CombineIdentifier { downstream.combineIdentifier }
    
    func receive(_ input: S.Input) -> Subscribers.Demand {
        downstream.receive(input)
    }
    
    func receive(subscription: any Subscription) {
        let newSubscription = Self(
            description: description,
            downstream: downstream,
            upstream: subscription
        )
        downstream.receive(subscription: newSubscription)
    }
    
    func receive(completion: Subscribers.Completion<S.Failure>) {
        downstream.receive(completion: completion)
    }
    
    func request(_ demand: Subscribers.Demand) {
        upstream?.request(demand)
    }
    
    func cancel() {
        upstream?.cancel()
    }
    
}
