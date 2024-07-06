//
//  TaskQos.swift
//  
//
//  Created by 박병관 on 7/6/24.
//
import Dispatch

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension JobPriority {
    
    func evaluateQos() -> DispatchQoS {
        if rawValue == DispatchQoS.unspecified.qosClass.rawValue.rawValue {
            return .unspecified
        }
        var value = DispatchQoS.QoSClass.userInteractive
        while true {
            let diff = Int(rawValue) - Int(value.rawValue.rawValue)
            // same
            if diff == 0 {
                return .init(qosClass: value, relativePriority: 0)
            }
            // current priority is higher than QOS
            // check for upgrade
            if diff > 0 {
                if value == .userInteractive {
                    return .userInteractive
                }
                // try to upgrade
                if let upgrade = value.up {
                    value = upgrade
                    continue
                } else {
                    return .unspecified
                }
            }
            // check for downgrade
            // relativePriority can only have negative ~ 0 priority
            // current priority is less or equal to next lower level
            if value == .background {
                // fallthrough
            } else if let downgrade = value.down {
                if rawValue <= downgrade.rawValue.rawValue {
                    value = downgrade
                    continue
                }
                // fallthrough
            } else {
                return .unspecified
            }
            // current priority is greater or equal to next lower level, but lower than current qos
            // use relativePriority!
            let relativePriority = max(Int(QOS_MIN_RELATIVE_PRIORITY), diff)
            return .init(qosClass: value, relativePriority: relativePriority)
        }
        return .unspecified
    }
    

}

extension DispatchQoS.QoSClass {
    
    var down:Self? {
        switch self {
        case .background:
            return nil
        case .utility:
            return .background
        case .default:
            return .utility
        case .userInitiated:
            return .default
        case .userInteractive:
            return .userInitiated
        case .unspecified:
            return nil
        @unknown default:
            return nil
        }
    }
    
    var up:Self? {
        switch self {
        case .background:
            return .utility
        case .utility:
            return .default
        case .default:
            return .userInitiated
        case .userInitiated:
            return .userInteractive
        case .userInteractive:
            return nil
        case .unspecified:
            return nil
        @unknown default:
            return nil
        }
    }
}


