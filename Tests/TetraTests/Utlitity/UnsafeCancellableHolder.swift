//
//  UnsafeCancellableHolder.swift
//
//
//  Created by 박병관 on 5/25/24.
//
import Combine
import Foundation

class UnsafeCancellableHolder {
    
    var bag = Set<AnyCancellable>()
}
