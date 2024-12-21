//
//  TetraExtended.swift
//  
//
//  Created by 박병관 on 6/27/24.
//
public import Namespace

public protocol TetraExtended {
    /// Type being extended.
    associatedtype Base

    /// Static Tetra extension point.
    @inlinable
    static var tetra: TetraExtension<Base>.Type { get }
    /// Instance Tetra extension point.
    @inlinable
    var tetra: TetraExtension<Base> { get }
}

extension TetraExtended where Base == Self {

    /// Static Tetra extension point.
    @inlinable
    public static var tetra: TetraExtension<Self>.Type {
        get { TetraExtension<Self>.self }
    }
    
    /// Instance Tetra extension point.
    @inlinable
    public var tetra: TetraExtension<Self> {
        get { TetraExtension(self) }
    }
    
}
