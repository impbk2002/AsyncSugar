//
//  Binding+Collection.swift
//  
//
//  Created by pbk on 2022/12/19.
//
//  Binding<MutableCollection>의 경우 iOS 15부터 Collection protocol를 지원한다.
// 그에 반해서 List(Binding<MutableCollection)은 
//

import Foundation
import SwiftUI

@available(watchOS, deprecated: 8.0, message: "use Binding<MutableCollection> itself as Collection")
@available(macOS, deprecated: 12.0, message: "use Binding<MutableCollection> itself as Collection")
@available(macCatalyst, deprecated: 15.0, message: "use Binding<MutableCollection> itself as Collection")
@available(tvOS, deprecated: 15.0, message: "use Binding<MutableCollection> itself as Collection")
public extension Binding where Value: MutableCollection {
    
    @inlinable
    var collection:BindingCollection<Value> {
        return .init(binding: self)
    }
    
}

@available(watchOS, deprecated: 8.0, message: "use Binding<MutableCollection> itself as Collection")
@available(macOS, deprecated: 12.0, message: "use Binding<MutableCollection> itself as Collection")
@available(macCatalyst, deprecated: 15.0, message: "use Binding<MutableCollection> itself as Collection")
@available(tvOS, deprecated: 15.0, message: "use Binding<MutableCollection> itself as Collection")
@available(iOS, deprecated: 15.0, message: "use Binding<MutableCollection> itself as Collection")
public struct BindingCollection<T:MutableCollection>: Collection {
    
    @usableFromInline
    @Binding var collection:T
    
    public typealias Element = Binding<T.Element>
    public typealias Index = T.Index
    public typealias Indices = T.Indices
    
    @inlinable
    public subscript(position: Index) -> Element {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, macOS 12.0, watchOS 8.0, *) {
            return binding[position]
        } else {
            nonisolated(unsafe)
            let index = position
            return .init { [binding] in
                binding.wrappedValue[index]
            } set: { [binding] newValue, transaction in
                nonisolated(unsafe)
                let ref = binding
                withTransaction(transaction) {
                    ref.wrappedValue[index] = newValue
                }
            }

        }
    }
    
    @usableFromInline
    internal var binding:Binding<T> { $collection }
    
    @inlinable
    public var startIndex: Index {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, macOS 12.0, watchOS 8.0, *) {
            return binding.startIndex
        } else {
            return collection.startIndex
        }
    }
    
    @inlinable
    public var endIndex: Index {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, macOS 12.0, watchOS 8.0, *) {
            return binding.endIndex
        } else {
            return collection.endIndex
        }
    }
    
    @inlinable
    public func index(after i: Index) -> Index {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, macOS 12.0, watchOS 8.0, *) {
            return binding.index(after: i)
        } else {
            return collection.index(after: i)
        }
    }
    
    @inlinable
    public func index(before i: Index) -> Index where T: BidirectionalCollection {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, macOS 12.0, watchOS 8.0, *) {
            return binding.index(before: i)
        } else {
            return collection.index(before: i)
        }
    }
    
    @inlinable
    public var indices: Indices {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, macOS 12.0, watchOS 8.0, *) {
            return binding.indices
        } else {
            return collection.indices
        }
    }

    

}

extension BindingCollection: BidirectionalCollection where T: BidirectionalCollection { }
extension BindingCollection: RandomAccessCollection where T: RandomAccessCollection { }

public extension BindingCollection {
    
    init(binding: Binding<T>) {
        self.init(collection: binding)
    }
    
}

