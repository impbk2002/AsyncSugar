//
//  conformance.swift
//  
//
//  Created by 박병관 on 6/27/24.
//
import CoreData
import Foundation
import Combine
public import Namespace

extension NSPersistentContainer: TetraExtended {}
extension NSPersistentStoreCoordinator: TetraExtended {}
extension NSManagedObjectContext: TetraExtended {}
extension NotificationCenter: TetraExtended {}
extension DispatchSource: TetraExtended {}
extension URLSession: TetraExtended {}
extension Task: TetraExtended {}

public extension Publisher {
    
    @inlinable
    var tetra:TetraExtension<Self> {
        .init(self)
    }
    
}
