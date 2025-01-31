//
//  mics.swift
//  
//
//  Created by pbk on 2022/12/08.
//

import Foundation
import Combine
import os




internal extension NSNumber {
    
    @usableFromInline
    final var isReal:Bool {
        cType == "d" || cType == "f"
    }

    @usableFromInline
    final var isInt:Bool {
        !isReal && CFGetTypeID(self) == CFNumberGetTypeID()
    }
    
    @usableFromInline
    final var isBool:Bool {
        CFGetTypeID(self) == CFBooleanGetTypeID()
    }
    
    @usableFromInline
    final var cType:String {
        String(cString: objCType)
    }
    


}
