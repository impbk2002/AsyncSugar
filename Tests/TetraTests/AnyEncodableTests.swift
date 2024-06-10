//
//  AnyEncodableTests.swift
//  
//
//  Created by pbk on 2023/01/27.
//

import XCTest
@testable import Tetra

final class AnyEncodableTests: XCTestCase {

    func testURLEncoding() throws {
        
        let targetURL = FileManager.default.temporaryDirectory
        
        XCTAssertEqual(
            try JSONEncoder().encode(AnyEncodable(targetURL)),
            try JSONEncoder().encode(targetURL)
        )
        
        XCTAssertNotEqual(
            try JSONEncoder().encode(AnyErasedEncodable(value: targetURL)),
            try JSONEncoder().encode(targetURL)
        )


    }

    
    func testURLObjectEncoding() throws {
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let objectForm = ["A": targetURL, "B": targetURL]
        let wrappedFrom = AnyEncodable(objectForm)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(objectForm)) as! NSDictionary,
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrappedFrom)) as! NSDictionary
        )
        
        XCTAssertEqual(
            try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(objectForm), format: nil) as! NSDictionary,
            try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(wrappedFrom), format: nil) as! NSDictionary
        )
    }
    
    func testURLArrayEncoding() throws {
        let targetURL = FileManager.default.temporaryDirectory
        let arrayForm = (0..<10).map{ _ in
            targetURL.appendingPathComponent(UUID().uuidString)
        }
        let wrappedFrom = AnyEncodable(arrayForm)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(arrayForm)) as! NSArray,
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrappedFrom)) as! NSArray
        )
        
        XCTAssertEqual(
            try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(arrayForm), format: nil) as! NSArray,
            try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(wrappedFrom), format: nil) as! NSArray
        )
    }
    
}
