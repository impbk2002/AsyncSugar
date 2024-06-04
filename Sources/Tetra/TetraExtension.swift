//
//  TetraExtension.swift
//  
//
//  Created by 박병관 on 1/1/24.
//

import Foundation

public struct TetraExtension<Base> {
    
    @usableFromInline
    internal var value:Base
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

public protocol TetraExtended {
    /// Type being extended.
    associatedtype Base

    /// Static Tetra extension point.
    @inlinable
    static var tetra: TetraExtension<Base>.Type { get set }
    /// Instance Tetra extension point.
    @inlinable
    var tetra: TetraExtension<Base> { get set }
}

extension TetraExtended {
    /// Static Tetra extension point.
    @inlinable
    public static var tetra: TetraExtension<Self>.Type {
        get { TetraExtension<Self>.self }
        set {}
    }

    /// Instance Tetra extension point.
    @inlinable
    public var tetra: TetraExtension<Self> {
        get { TetraExtension(self) }
        set {}
    }
}

