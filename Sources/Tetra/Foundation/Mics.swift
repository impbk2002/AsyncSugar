//
//  mics.swift
//  
//
//  Created by pbk on 2022/12/08.
//

import Foundation
import Combine
import os




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
func wrapToResult<T:~Copyable,Failure:Error>(_ block: () throws(Failure) -> T) -> Result<T,Failure> {
    do {
        return .success(try block())
    } catch {
        return .failure(error)
    }
}


@inline(__always)
@usableFromInline
internal func wrapToResult<T:~Copyable,Failure:Error, U:~Copyable>(
    _ value: consuming T, _ transform: (consuming T) async throws(Failure) -> sending U
) async -> sending Result<U,Failure> {
    do {
        let success = try await transform(value)
        return .success(success)
    } catch {
        return .failure(error)
    }
}
