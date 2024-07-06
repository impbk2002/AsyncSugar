//
//  TaskQos.swift
//  
//
//  Created by 박병관 on 7/6/24.
//
import Dispatch

extension TaskPriority {
    
    func evaluateQos() -> DispatchQoS {
        let userInteractive = TaskPriority.userInteractive
        switch self {
        case userInteractive:
            return .userInteractive
        case .high:
            return .userInitiated
        case .medium:
            return .default
        case .low:
            return .utility
        case .background:
            return .background
        case .unspecified:
            return .unspecified
        default:
            break
        }
        if self > userInteractive {
            return .userInteractive
        }
        let calculate = { (basis: TaskPriority) in
            let diff = basis.rawValue - self.rawValue
            return max(-Int(diff), Int(QOS_MIN_RELATIVE_PRIORITY))
        }
        if self < .background {
            return .init(qosClass: .background, relativePriority: calculate(.background))
        }
        if (TaskPriority.userInitiated..<userInteractive).contains(self) {
            return .init(qosClass: .userInteractive, relativePriority: calculate(userInteractive))
        }
        if (TaskPriority.medium..<TaskPriority.userInitiated).contains(self) {
            return .init(qosClass: .userInitiated, relativePriority: calculate(.userInitiated))
        }
        if (TaskPriority.low..<TaskPriority.medium).contains(self) {
            return .init(qosClass: .default, relativePriority: calculate(.medium))
        }
        if (TaskPriority.background..<TaskPriority.low).contains(self) {
            return .init(qosClass: .utility, relativePriority: calculate(.low))
        }
        return .unspecified
    }
    
}

extension DispatchQoS {
    
    func evaluateTaskPriority() -> TaskPriority? {
        let evaluate = { (base:TaskPriority) in
            let rawValue = Int8(bitPattern: base.rawValue) + Int8(relativePriority)
            return TaskPriority(rawValue: UInt8(bitPattern: rawValue))
        }
        switch qosClass {
        case .userInteractive:
            return evaluate(.userInteractive)
        case .userInitiated:
            return evaluate(.high)
        case .default:
            return evaluate(.medium)
        case .utility:
            return evaluate(.low)
        case .background:
            return evaluate(.background)
        default:
            return nil
        }
        
    }
    
}


@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension JobPriority {
    
    func evaluateQos() -> DispatchQoS {
        return TaskPriority(rawValue: rawValue).evaluateQos()
    }
    

}

