//
//  UnsafeCancellableHolder.swift
//
//
//  Created by 박병관 on 5/25/24.
//
import Combine
import Foundation
@preconcurrency
class UnsafeCancellableHolder {
    
    var bag = Set<AnyCancellable>()
}
