//
//  AnyEncodableTests.swift
//  
//
//  Created by pbk on 2023/01/27.
//
import Foundation
@testable import Tetra
import Testing

@Suite
struct AnyEncodableTests {

    @Test
    func testURLEncoding() throws {
        
        let targetURL = FileManager.default.temporaryDirectory
        let defaultValue =  try JSONEncoder().encode(targetURL)
        let anyValue = try JSONEncoder().encode(AnyEncodable(targetURL))
        let erasedValue = try JSONEncoder().encode(AnyErasedEncodable(value: targetURL))
        #expect(defaultValue == anyValue)
        #expect(defaultValue != erasedValue)
    }
    

    @Test
    func testURLObjectEncoding() throws {
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let objectForm = ["A": targetURL, "B": targetURL]
        let wrappedFrom = AnyEncodable(objectForm)
        var wrappedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrappedFrom)) as! NSDictionary
        var rawObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(objectForm)) as! NSDictionary
        #expect(wrappedObject == rawObject)
        rawObject = try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(objectForm), format: nil) as! NSDictionary
        wrappedObject = try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(wrappedFrom), format: nil) as! NSDictionary
        #expect(rawObject == wrappedObject)
    }
    
    @Test
    func testURLArrayEncoding() throws {
        let targetURL = FileManager.default.temporaryDirectory
        let arrayForm = (0..<10).map{ _ in
            targetURL.appendingPathComponent(UUID().uuidString)
        }
        let wrappedFrom = AnyEncodable(arrayForm)
        var rawArray = try JSONSerialization.jsonObject(with: JSONEncoder().encode(arrayForm)) as! NSArray
        var wrappedArray = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrappedFrom)) as! NSArray
        #expect(rawArray == wrappedArray)
        rawArray = try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(arrayForm), format: nil) as! NSArray
        wrappedArray = try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(wrappedFrom), format: nil) as! NSArray
        #expect(rawArray == wrappedArray)
    }
    
}
