//
//  Future+Concurrency.swift
//  
//
//  Created by pbk on 2022/12/26.
//

import Foundation
import Combine
import Namespace

extension TetraExtension where Base: _CombineFuterProtocol {
    
    @inlinable
    public var value:Base.Output {
        get async throws(Base.Failure) {
            let future = base._tetraFuture
            // subscriber inferface is guaranteed to be called serially, so we can use variable without lock happily :)
            var subscription: (any Subscription)? = nil
            defer {
                withExtendedLifetime(subscription, { })
            }
            let result: Result<Base.Output,Base.Failure> = await withCheckedContinuation { continuation in
                future.subscribe(AnySubscriber(
                    receiveSubscription: {
                        $0.request(.max(1))
                        subscription = $0
                    },
                    receiveValue: { (value: sending Base.Output) in
                        continuation.resume(returning: .success(value))
                        return .none
                    },
                    receiveCompletion: {
                        if case let .failure(error) = $0 {
                            continuation.resume(returning: .failure(error))
                        }
                        subscription = nil
                    }
                ))
            }
            switch result {
            case .success(let success):
                return success
            case .failure(let failure):
                throw failure
            }
            
        }
    }
    
}

public protocol _CombineFuterProtocol: Publisher {

    @inlinable
    var _tetraFuture: Combine.Future<Output,Failure> { get }
    
}

extension Combine.Future: _CombineFuterProtocol {
    
    @inlinable
    public var _tetraFuture: Future<Output, Failure> { self }
    
}
