//
//  Future+Concurrency.swift
//  
//
//  Created by pbk on 2022/12/26.
//

import Foundation
import Combine



public extension Combine.Future {
    
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(watchOS, deprecated: 8, renamed: "value")
    @available(macOS, deprecated: 12.0, renamed: "value")
    @inlinable
    final var compatValue: Output {
        get async throws(Failure) {
            let result: Result<Output,Failure> = await withCheckedContinuation { continuation in
                self.subscribe(AnySubscriber(
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
    
}
