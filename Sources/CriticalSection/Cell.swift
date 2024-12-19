//
//  Cell.swift
//
//
//  Created by 박병관 on 6/26/24.
//
import Builtin
import Synchronization
#if $BuiltinAddressOfRawLayout

@frozen
@usableFromInline
@_rawLayout(like: Value, movesAsLike)
internal struct _Cell<Value: ~Copyable>: ~Copyable {

    @_transparent
    @usableFromInline
    internal var _address: UnsafeMutablePointer<Value> {
        UnsafeMutablePointer<Value>(_rawAddress)
    }
    
    @_transparent
    @usableFromInline
    internal var _rawAddress: Builtin.RawPointer {
        Builtin.addressOfRawLayout(self)
    }
    
    @_transparent
    @usableFromInline
    internal init(_ initialValue: consuming Value) {
        _address.initialize(to: initialValue)
    }
    
    @inlinable
    deinit {
        _address.deinitialize(count: 1)
    }
    
}

#endif
