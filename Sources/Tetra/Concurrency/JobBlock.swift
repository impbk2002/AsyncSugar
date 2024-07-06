//
//  JobBlock.swift
//  
//
//  Created by 박병관 on 6/30/24.
//
import Darwin

@usableFromInline
struct JobBlock: Hashable, Comparable, Sendable {
    
    @usableFromInline
    let id:Int
    @usableFromInline
    let jobImp:UnownedJob
    nonisolated(unsafe)
    var token:pthread_override_t?
    
    @usableFromInline
    var priority:UInt8 {
        if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
            jobImp.priority.rawValue
        } else {
            0
        }
    }
    
    @usableFromInline
    @available(macOS 14.0, *)
    init(id: Int, job: consuming ExecutorJob) {
        self.id = id
        self.jobImp = UnownedJob(job)
        
    }
    
    @usableFromInline
    init(id: Int, jobRef: UnownedJob) {
        self.id = id
        self.jobImp = jobRef
    }
    
    @usableFromInline
    func hash(into hasher: inout Hasher) {
        hasher.combine(priority)
    }
    
    @usableFromInline
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    
    @usableFromInline
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.id < rhs.id
        }
        return lhs.priority < rhs.priority
    }
    
    @usableFromInline
    static func > (lhs:Self, rhs:Self) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.id > rhs.id
        }
        return lhs.priority > rhs.priority
    }

}

