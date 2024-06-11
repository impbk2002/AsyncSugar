//
//  mics.swift
//  
//
//  Created by pbk on 2022/12/08.
//

import Foundation
import Combine
import os

internal enum SubscriptionStatus {
    case awaitingSubscription
    case subscribed(any Subscription)
    case terminal
    
    var subscription:Subscription? {
        guard case .subscribed(let subscription) = self else {
            return nil
        }
        return subscription
    }
    
}



@rethrows
@usableFromInline
internal protocol _ErrorMechanism {
    associatedtype Output
    func get() throws -> Output
}

extension _ErrorMechanism {
    // rethrow an error only in the cases where it is known to be reachable
    
    @usableFromInline
    internal func _rethrowOrFail() rethrows -> Never {
        _ = try _rethrowGet()
        fatalError("materialized error without being in a throwing context")
    }

    @usableFromInline
    internal func _rethrowGet() rethrows -> Output {
        return try get()
    }
}

extension Result: _ErrorMechanism { }



internal extension NSNumber {
    
    @usableFromInline
    final var isReal:Bool {
        cType == "d" || cType == "f"
    }

    @usableFromInline
    final var isInt:Bool {
        !isReal && CFGetTypeID(self) == CFNumberGetTypeID()
    }
    
    @usableFromInline
    final var isBool:Bool {
        CFGetTypeID(self) == CFBooleanGetTypeID()
    }
    
    @usableFromInline
    final var cType:String {
        String(cString: objCType)
    }
    


}

@inline(__always)
@usableFromInline
internal
func wrapToResult<T,Failure:Error>(_ block: () throws(Failure) -> T) -> Result<T,Failure> {
    do {
        return .success(try block())
    } catch {
        return .failure(error)
    }
}

@inline(__always)
@usableFromInline
internal
func wrapToResult<Base: TypedAsyncIteratorProtocol & AsyncIteratorProtocol>(
    _ actor: isolated (any Actor)?,
    _ iterator: inout Base
) async -> sending Result<Base.Element,Base.Failure>? {
    do {
        if let value = try await iterator.next(isolation: actor) {
            return .success(value)
        }
        return nil
//        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
//            let value = try await iterator.next(isolation: actor)
//            if let value {
//                return .success(value)
//            } else {
//                return nil
//            }
//        } else {
//            let result = try await iterator.next()
//            return result
//        }
    } catch {
        return .failure(error)
    }
}


@inline(__always)
@usableFromInline
internal func wrapToResult<T,Failure:Error, U>(_ value:T, _ transform: (T) async throws(Failure) -> U) async -> sending Result<U,Failure> {
    do {
        let success = try await transform(value)
        return .success(success)
    } catch {
        return .failure(error)
    }
}
