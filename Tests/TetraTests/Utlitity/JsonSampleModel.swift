//
//  JsonSampleModel.swift
//  
//
//  Created by pbk on 2023/05/30.
//

import Foundation

struct JsonSample1Model: Codable, Hashable {
    
    
    var imaging:[LocationItem]
    var labs:[LocationItem]
    
    
    
    struct LocationItem: Codable, Hashable {
        
        var location:String
        var name:String
        var time:String
        
    }
    
    struct Medical: Codable, Hashable {
        
        var aceInhibitors:[MetaData]
        var antianginal:[MetaData]
        var anticoagulants:[MetaData]
        var betaBlocker:[MetaData]
        var diuretic:[MetaData]
        var mineral:[MetaData]
        
        struct MetaData: Codable, Hashable {
            
            var does:String
            var name:String
            var pillCount:String
            var refills:String
            var route:String
            var sig:String
            var strength:String
        }
        
    }
    
    
}

struct JsonSample2Model: Codable, Hashable {
    
    var insureCode:[InsureItem]
    struct InsureItem: Codable, Hashable {
        
        var sq_code_insure:Int
        var cd_code:String
        var ty_code:String
        var nm_code:String
        var no_order:Int
        var no_rank:Int
        
    }
}

typealias JsonSample3Model = [JsonSample3Item]

struct JsonSample3Item: Codable, Hashable {
    
    
    var BCSEA2:String
    var BCCODE:String
    var BCBIZTYPE:String
}
