//
//  JsonWrapperTests.swift
//  
//
//  Created by pbk on 2023/01/31.
//

import XCTest
@testable import Tetra

final class JsonWrapperTests: XCTestCase {


    func testMappingPerformance() throws {
//        let json1 = try Data(contentsOf: Bundle.module.url(forResource: "JsonSample1", withExtension: "json").unsafelyUnwrapped)
//        let json2 = try Data(contentsOf: Bundle.module.url(forResource: "JsonSample2", withExtension: "json").unsafelyUnwrapped)
        let json3 = try Data(contentsOf: Bundle.module.url(forResource: "JsonSample3", withExtension: "json").unsafelyUnwrapped)
        measure {

            do {
//                let _ = try JSONSerialization.jsonObject(with: json3)
                let _ = try JsonWrapper.init(from: json3)
//                let _ = try JSONDecoder().decode([[String:String]].self, from: json3)
            } catch {
                print(error)
                XCTFail(error.localizedDescription)
            }

        }
        
    }
    
    func testNumeric() throws {
        
        let sample = Data("""
{"a": 0.0, "b": 1, "K":true}
""".utf8)
        
        XCTAssertEqual(try JsonWrapper(from: sample), ["a": 0.0, "b": 1, "K":true])
    }
    
    func testCustomDecoder1() throws {
        try runCustomDecoder(
            JsonSample1Model.self,
            url: XCTUnwrap(
                Bundle.module.url(forResource: "JsonSample1", withExtension: "json")
            )
        )
    }
    
    func testCustomDecoder2() throws {
        try runCustomDecoder(
            JsonSample2Model.self,
            url: XCTUnwrap(
                Bundle.module.url(forResource: "JsonSample2", withExtension: "json")
            )
        )
    }
    
    func testCustomDecoder3() throws {
        try runCustomDecoder(
            JsonSample3Model.self,
            url: XCTUnwrap(
                Bundle.module.url(forResource: "JsonSample3", withExtension: "json")
            )
        )
    }
    
    private func runCustomDecoder<T:Decodable& Equatable>(_ type:T.Type, url:URL) throws {
        let data = try Data(contentsOf: url)
        let model = try JSONDecoder().decode(type, from: data)
        let jsonWrapper = try JsonWrapper(from: data)
        let model2 = try JsonWrapperDecoder().decode(type, from: jsonWrapper)
        XCTAssertEqual(model, model2)
    }
    
    private func runCustomEncoder<T:Codable>(_ value:T) throws {
        let data = try JSONEncoder().encode(value)
        let jsonWrapper = try JSONSerialization.jsonObject(with: data) as! NSObject
        let model = try JsonWrapperEncoder().encode(value).propertyObject as! NSObject
        XCTAssertEqual(model, jsonWrapper)
    }
    
    
    func testCustomEncoder1() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "JsonSample1", withExtension: "json"))
        let model = try JSONDecoder().decode(JsonSample1Model.self, from: Data(contentsOf: url))
        try runCustomEncoder(model)
    }

    func testCustomEncoder2() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "JsonSample2", withExtension: "json"))
        let model = try JSONDecoder().decode(JsonSample2Model.self, from: Data(contentsOf: url))
        try runCustomEncoder(model)
    }
    
    func testCustomEncoder3() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "JsonSample3", withExtension: "json"))
        let model = try JSONDecoder().decode(JsonSample3Model.self, from: Data(contentsOf: url))
        try runCustomEncoder(model)
    }
    
}
