//
//  EitherFailure.swift
//  
//
//  Created by 박병관 on 6/22/24.
//

enum EitherFailure<First:Error, Second:Error>:Error {
    
    case first(First)
    case second(Second)
}
