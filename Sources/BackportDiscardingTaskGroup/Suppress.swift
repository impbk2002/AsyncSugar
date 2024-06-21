//
//  Suppress.swift
//  
//
//  Created by 박병관 on 6/20/24.
//

@preconcurrency
@usableFromInline
struct Suppress<Base>:@unchecked Sendable {
    
    @usableFromInline
    nonisolated(unsafe)
    var base:Base
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
    
}
