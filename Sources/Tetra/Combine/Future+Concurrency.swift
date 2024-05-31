//
//  Future+Concurrency.swift
//  
//
//  Created by pbk on 2022/12/26.
//

import Foundation
import Combine

public extension Combine.Future where Failure == Never {
    
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(watchOS, deprecated: 8, renamed: "value")
    @available(macOS, deprecated: 12.0, renamed: "value")
    @inlinable
    final var compatValue: Output {
        get async {
            if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
                return await value
            } else {
                return await withCheckedContinuation{ continuation in
                    self.subscribe(AnySubscriber(
                        receiveSubscription: {
                            $0.request(.max(1))
                        },
                        receiveValue: {
                            continuation.resume(returning: $0)
                            return .none
                        }
                    ))
                }
            }
        }
    }
    
}


public extension Combine.Future {
    
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(iOS, deprecated: 15.0, renamed: "value")
    @available(watchOS, deprecated: 8, renamed: "value")
    @available(macOS, deprecated: 12.0, renamed: "value")
    @inlinable
    final var compatValue: Output {
        get async throws {
            if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
                return try await value
            } else {
                let result: Result<Output,Failure> = await withCheckedContinuation { continuation in
                    self.subscribe(AnySubscriber(
                        receiveSubscription: {
                            $0.request(.max(1))
                        },
                        receiveValue: {
                            continuation.resume(returning: .success($0))
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
    
}
