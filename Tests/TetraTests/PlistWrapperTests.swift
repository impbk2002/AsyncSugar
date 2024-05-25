//
//  PlistWrapperTests.swift
//  
//
//  Created by pbk on 2023/05/30.
//

import XCTest
@testable import Tetra

final class PlistWrapperTests: XCTestCase {

    
    func testDataArraySerialization() throws {
        let data = Data(UUID().uuidString.utf8)
        let wrapper:PlistWrapper = [.data(data)]
        let actual = NSArray(object: (data as NSData))
        let pEncoder = PropertyListEncoder()
        pEncoder.outputFormat = .xml
        let serializedXMLData = try PropertyListSerialization.data(fromPropertyList: actual, format: .xml, options: 0)
        let encodedXMLData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedXMLData, encodedXMLData)
        pEncoder.outputFormat = .binary
        let serializedBinaryData = try PropertyListSerialization.data(fromPropertyList: actual, format: .binary, options: 0)
        let encodedBinaryData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedBinaryData, encodedBinaryData)
    }
    
    func testDataDictionarySerialization() throws {
        let object = ["A": Data(UUID().uuidString.utf8)]
        let wrapper:PlistWrapper = .object(object.mapValues{ .data($0) })
        let actual = object as NSDictionary
        let pEncoder = PropertyListEncoder()
        pEncoder.outputFormat = .xml
        let serializedXMLData = try PropertyListSerialization.data(fromPropertyList: actual, format: .xml, options: 0)
        let encodedXMLData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedXMLData, encodedXMLData)
        pEncoder.outputFormat = .binary
        let serializedBinaryData = try PropertyListSerialization.data(fromPropertyList: actual, format: .binary, options: 0)
        let encodedBinaryData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedBinaryData, encodedBinaryData)
    }
    
    func testDateArraySerialization() throws {
        let date = Date()
        let wrapper:PlistWrapper = [.date(date)]
        let actual = NSArray(object: (date as NSDate))
        let pEncoder = PropertyListEncoder()
        pEncoder.outputFormat = .xml
        let serializedXMLData = try PropertyListSerialization.data(fromPropertyList: actual, format: .xml, options: 0)
        let encodedXMLData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedXMLData, encodedXMLData)
        pEncoder.outputFormat = .binary
        let serializedBinaryData = try PropertyListSerialization.data(fromPropertyList: actual, format: .binary, options: 0)
        let encodedBinaryData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedBinaryData, encodedBinaryData)
    }
    
    func testDateDictionarySerialization() throws {
        let object = [
            UUID().uuidString: Date()
        ]
        let wrapper:PlistWrapper = .object(object.mapValues{ .date($0) })
        let actual = object as NSDictionary
        let pEncoder = PropertyListEncoder()
        pEncoder.outputFormat = .xml
        let serializedXMLData = try PropertyListSerialization.data(fromPropertyList: actual, format: .xml, options: 0)
        let encodedXMLData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedXMLData, encodedXMLData)
        pEncoder.outputFormat = .binary
        let serializedBinaryData = try PropertyListSerialization.data(fromPropertyList: actual, format: .binary, options: 0)
        let encodedBinaryData = try pEncoder.encode(wrapper)
        XCTAssertEqual(serializedBinaryData, encodedBinaryData)
    }
    
    func testCustomDecoder1() throws {
        try runCustomDecoder(
            JsonSample1Model.self,
            url: XCTUnwrap(
                Bundle.module.url(forResource: "PlistSample1", withExtension: "plist")
            )
        )
    }
    
    func testCustomDecoder2() throws {
        try runCustomDecoder(
            JsonSample2Model.self,
            url: XCTUnwrap(
                Bundle.module.url(forResource: "PlistSample2", withExtension: "plist")
            )
        )
    }
    
    func testCustomDecoder3() throws {
        try runCustomDecoder(
            JsonSample3Model.self,
            url: XCTUnwrap(
                Bundle.module.url(forResource: "PlistSample3", withExtension: "plist")
            )
        )
    }
    
    private func runCustomDecoder<T:Decodable& Equatable>(_ type:T.Type, url:URL) throws {
        let data = try Data(contentsOf: url)
        let model = try PropertyListDecoder().decode(type, from: data)
        let jsonWrapper = try PlistWrapper(from: data)
        let model2 = try PlistWrapperDecoder().decode(type, from: jsonWrapper)
        XCTAssertEqual(model, model2)
    }
    
    private func runCustomEncoder<T:Codable>(_ value:T) throws {
        let data = try PropertyListEncoder().encode(value)
        let jsonWrapper = try PropertyListSerialization.propertyList(from: data, format: nil) as! NSObject
        let model = try PlistWrapperEncoder().encode(value).propertyObject as! NSObject
        XCTAssertEqual(model, jsonWrapper)
    }
    
    
    func testCustomEncoder1() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PlistSample1", withExtension: "plist"))
        let model = try PropertyListDecoder().decode(JsonSample1Model.self, from: Data(contentsOf: url))
        try runCustomEncoder(model)
    }

    func testCustomEncoder2() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PlistSample2", withExtension: "plist"))
        let model = try PropertyListDecoder().decode(JsonSample2Model.self, from: Data(contentsOf: url))
        try runCustomEncoder(model)
    }
    
    func testCustomEncoder3() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PlistSample3", withExtension: "plist"))
        let model = try PropertyListDecoder().decode(JsonSample3Model.self, from: Data(contentsOf: url))
        try runCustomEncoder(model)
    }

}
