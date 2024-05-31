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
    
    public init(_ base: Base) {
        self.base = base
    }
    
}


extension TetraExtension: Sendable where Base:Sendable {}

public protocol TetraExtended {
    /// Type being extended.
    associatedtype Base

    /// Static Tetra extension point.
    static var tetra: TetraExtension<Base>.Type { get set }
    /// Instance Tetra extension point.
    var tetra: TetraExtension<Base> { get set }
}

extension TetraExtended {
    /// Static Tetra extension point.
    public static var tetra: TetraExtension<Self>.Type {
        get { TetraExtension<Self>.self }
        set {}
    }

    /// Instance Tetra extension point.
    public var tetra: TetraExtension<Self> {
        get { TetraExtension(base: self) }
        set {}
    }
}

