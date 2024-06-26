//
//  Future+Concurrency.swift
//  
//
//  Created by pbk on 2022/12/26.
//

import Foundation
import Combine


extension TetraExtension {

    @inlinable
    public func next<Output,Failure:Error>() async throws(Failure) -> Output where Base == Combine.Future<Output,Failure> {
        let result: Result<Output,Failure> = await withCheckedContinuation { continuation in
            base.subscribe(AnySubscriber(
                receiveSubscription: {
                    $0.request(.max(1))
                },
                receiveValue: { (value: sending Output) in
                    continuation.resume(returning: .success(value))
                    return .none
                },
                receiveCompletion: {
                    if case let .failure(error) = $0 {
                        continuation.resume(returning: .failure(error))
                    }
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
