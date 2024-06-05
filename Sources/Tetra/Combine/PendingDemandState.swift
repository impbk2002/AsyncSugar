//
//  File.swift
//  
//
//  Created by 박병관 on 5/29/24.
//

import Foundation
import Combine

struct PendingDemandState {
    private var taskCount:Int
    private var pendingDemand:Subscribers.Demand
    
    
    init() {
        self.taskCount = 0
        self.pendingDemand = .none
    }
    
    mutating func transistion(
        maxTasks:Subscribers.Demand,
        _ demand:Subscribers.Demand,
        reduce:Bool = false
    ) -> (Subscribers.Demand) {
        if maxTasks == .unlimited {
            return demand
        }
        if reduce {
            taskCount -= 1
        }
        pendingDemand += demand
        let availableSpace = maxTasks - taskCount
        if pendingDemand >= availableSpace {
            pendingDemand -= availableSpace
            if let maxCount = availableSpace.max {
                taskCount += maxCount
            } else {
                fatalError("availableSpace can not be unlimited while limit is bounded")
            }
            return availableSpace
        } else {
            let snapShot = pendingDemand
            if let count = snapShot.max {
                taskCount += count
                pendingDemand = .none
            } else {
                // pendingDemand is smaller than availableSpace and limit is bounded and pendingDemand is infinite
                fatalError("pendingDemand can not be unlimited while limit is bounded")
            }
            return snapShot
        }
    }


    
}
