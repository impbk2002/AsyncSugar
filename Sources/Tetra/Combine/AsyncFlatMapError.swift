//
//  AsyncFlatMapError.swift
//  
//
//  Created by 박병관 on 6/9/24.
//

import Foundation


@usableFromInline
enum AsyncFlatMapError<First:Error, Second:Error, Third:Error>: Error {
    
    case upstream(First)
    case transform(Second)
    case segment(Third)
    
}


extension AsyncFlatMapError{
    
    @inlinable
    func unwrap() -> Never where First == Second, Second == Third, Third == Never {
        fatalError()
    }
    
    @inlinable
    func unwrap() -> First where First == Second, Second == Third {
        switch self {
        case .upstream(let error):
            fallthrough
        case .segment(let error):
            fallthrough
        case .transform(let error):
            return (error)
        }
    }
    
    @inlinable
    func unwrap() -> First where First == Second, Third == Never {
        switch self {
        case .upstream(let error):
            fallthrough
        case .transform(let error):
            return error

        }
    }
    
    @inlinable
    func unwrap() -> Second where Second == Third, First == Never {
        switch self {
        case .transform(let error):
            fallthrough
        case .segment(let error):
            return error
        }
    }
    
    @inlinable
    func unwrap() -> Third where First == Third, Second == Never {
        switch self {
        case .upstream(let error):
            fallthrough
        case .segment(let error):
            return error
        }
    }
    
    @inlinable
    func unwrap() -> First where Second == Third, Third == Never {
        switch self {
        case .upstream(let error):
            return error
        }
    }
    
    @inlinable
    func unwrap() -> Second where First == Third, First == Never {
        switch self {
        case .transform(let error):
            return error
        }
    }
    
    @inlinable
    func unwrap() -> Third where First == Second, Second == Never {
        switch self {
        case .segment(let error):
            return error
        }
    }
    
    
}

