//
//  Untitled.swift
//  
//
//  Created by 박병관 on 6/13/24.
//
import Darwin

public enum BackPort {
    
}


import Synchronization
import Builtin
//
//
//@_rawLayout(like: os_unfair_lock, movesAsLike)
//@usableFromInline
//package struct UnfairPrimitive: ~Copyable {
//    
//    @inlinable
//    package init() {
//        pointer.initialize(to: .init())
//    }
//    
//    @usableFromInline
//    internal var pointer:UnsafeMutablePointer<os_unfair_lock> {
//        withUnsafePointer(to: self) {
//            UnsafeMutableRawPointer(mutating: $0).assumingMemoryBound(to: os_unfair_lock.self)
//        }
//    }
//    
//    @inlinable
//    borrowing package func lock() {
//        UnsafeMutableRawPointer(Builtin.addressOfRawLayout(self))
//        os_unfair_lock_lock(pointer)
//    }
//    
//    @inlinable
//    borrowing package func unlock() {
//        os_unfair_lock_unlock(pointer)
//    }
//    
//    @inlinable
//    borrowing package func tryLock() -> Bool {
//        os_unfair_lock_trylock(pointer)
//    }
//    
//    
//}
