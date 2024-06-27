//
//  TetraExtension.swift
//  
//
//  Created by 박병관 on 1/1/24.
//

import Foundation

public struct TetraExtension<Base> {
    
    @usableFromInline
    package var value:Base
    
    @inlinable
    public var base:Base {
        get { value }
    }
    
    @inlinable
    public init(base: Base) {
        self.value = base
    }
    
    @inlinable
    public init(_ base: Base) {
        self.value = base
    }
    

}


extension TetraExtension: Sendable where Base:Sendable {}

