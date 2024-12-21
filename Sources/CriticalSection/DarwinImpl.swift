//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Atomics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if $BuiltinAddressOfRawLayout && canImport(Darwin)
import Darwin

@frozen
@_staticExclusiveOnly
public struct _MutexHandle: ~Copyable {
  @usableFromInline
  let value: _Cell<os_unfair_lock>

  @_transparent
  public init() {
    value = _Cell(os_unfair_lock())
  }

  @_transparent
  internal borrowing func _lock() {
    os_unfair_lock_lock(value._address)
  }

  @_transparent
  internal borrowing func _tryLock() -> Bool {
    os_unfair_lock_trylock(value._address)
  }


  @_transparent
  internal borrowing func _unlock() {
    os_unfair_lock_unlock(value._address)
  }
}

#endif
