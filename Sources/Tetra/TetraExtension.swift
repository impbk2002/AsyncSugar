//
//  TetraExtension.swift
//  
//
//  Created by 박병관 on 1/1/24.
//

import Foundation

public struct TetraExtension<Base> {
    
    public internal(set) var base:Base
    
    public init(base: Base) {
        self.base = base
    }
}

extension TetraExtension: Sendable where Base:Sendable {}
