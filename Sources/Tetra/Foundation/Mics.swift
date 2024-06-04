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

@usableFromInline
internal
func wrapToResult<T,Failure:Error>(_ block: () throws(Failure) -> T) -> Result<T,Failure> {
    do {
        return .success(try block())
    } catch {
        return .failure(error)
    }
}

@usableFromInline
internal
func wrapToResult<Base: AsyncIteratorProtocol>(_ iterator: inout Base) async -> Result<Base.Element,Base.Failure>? {
    do {
        let value = try await iterator.next(isolation: nil)
        if let value {
            return .success(value)
        } else {
            return nil
        }
    } catch {
        return .failure(error)
    }
}
