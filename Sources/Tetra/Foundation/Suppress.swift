//
//  Suppress.swift
//
//
//  Created by 박병관 on 6/11/24.
//

// just using to suppress sendable check for unsafe concurrent operation
@usableFromInline
struct Suppress<T>: @unchecked Sendable {
    
    var value:T
    
    @usableFromInline
    init(value: T) {
        self.value = value
    }
    
}
