//
//  File.swift
//  Tetra
//
//  Created by 박병관 on 1/27/25.
//

import Foundation
@preconcurrency import CoreFoundation
@_implementationOnly private import TetraConcurrentQueueShim
//private import CriticalSection
//private import Atomics

struct StateStorage {
    
//    fileprivate let lock: some UnfairLockProtocol = createUnfairLock()
//    var registry = [CFRunLoop: Set<String>]()
    var serialRef: UnownedSerialExecutor
//    fileprivate let reference = ManagedAtomicLazyReference<CFRunLoop>()

    var taskRef:AnyObject? = nil
    
}



final class RunLoopStorageBufferHolder {}



final package class TetraRunLoopExecutor: NSObject {
    

    let source: CFRunLoopSource
    
    deinit {
        CFRunLoopSourceInvalidate(source)
//        runLoop.perform {}
        
    }

    @objc
    package override convenience init() {
        self.init(name: nil)
    }
    
    @nonobjc
    package init(
        name: String?
    ) {


        var bufferPtr = ManagedBufferPointer<StateStorage,Void>(bufferClass: RunLoopStorageBufferHolder.self, minimumCapacity: 0) { buffer, capacity in
                .init(serialRef: MainActor.sharedUnownedExecutor)
        }

        self.source = withUnsafePointer(to: TetraContextData(
            perform: tetra_runLoop_drainSource,
            schedule: tetra_runLoop_schedule_cb,
            cancel: tetra_runLoop_cancel_cb
        )) {
            create_tetra_runLoop_executor(bufferPtr.buffer, $0)
        }
        super.init()
        // override serialExecutor to the correct value
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            bufferPtr.header.taskRef = ManagedBufferPointer<UnownedTaskExecutor,Void>(bufferClass: RunLoopStorageBufferHolder.self, minimumCapacity: 0, makingHeaderWith: { buffer, capacity in
                return asUnownedTaskExecutor()
            }).buffer
        }
        bufferPtr.header.serialRef = asUnownedSerialExecutor()
        let thread = Thread(block: runLoopThreadRun)
        thread.threadDictionary["source"] = self.source
        if let name = name {
            thread.name = name
        }
        thread.qualityOfService = .default
        thread.start()

    }
    
}




extension TetraRunLoopExecutor : SerialExecutor {}

extension TetraRunLoopExecutor: TaskExecutor {}

package extension TetraRunLoopExecutor {
    
    @objc
    nonisolated func copyCurrentRegistry() -> [CFRunLoop:Set<String>] {
        return copy_tetra_runLoop_registry(source) as! [CFRunLoop:Set<String>]
    }
    
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    nonisolated func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }
    
    nonisolated func enqueue(_ job: UnownedJob) {
        tetra_enqueue_and_signal(source, job as AnyObject)
    }
    
    nonisolated func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
            return .init(complexEquality: self)
        }
        return .init(ordinary: self)
    }
    
    nonisolated func checkIsolated() {
//        let currentMode = RunLoop.current.currentMode.flatMap{ $0.rawValue
//            as CFString }.flatMap{ CFRunLoopMode($0)}
        precondition(
//            currentMode != nil &&
            CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode),
            "TetraRunLoopExecutor must be called from the RunLoop that it was created on."
        )
    }
    
    
    
}

extension TetraRunLoopExecutor {
    
    nonisolated package func register(_ runLoop: CFRunLoop) {
        CFRunLoopAddSource(runLoop, source, .defaultMode)
    }
    
    nonisolated package func register(_ runLoop:RunLoop) {
        CFRunLoopAddSource(runLoop.getCFRunLoop(), source, .defaultMode)
    }
    
    @available(swift, obsoleted: 1.0)
    @objc
    package func schedule( _ block: @convention(block) () -> Void) {
        block()
    }
    
}


fileprivate nonisolated func runLoopThreadRun() {
    let source = Thread.current.threadDictionary["source"] as! CFRunLoopSource
    Thread.current.threadDictionary["source"] = nil
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
    while CFRunLoopSourceIsValid(source), RunLoop.current.run(mode: .default, before: .distantFuture) {

    }
    
}

private func tetra_runLoop_drainSource(_ stateRef:CFTypeRef, _ jobRef:CFArray) {
    let buffPtr = ManagedBufferPointer<StateStorage,Void>(unsafeBufferObject: stateRef)
    let serials = buffPtr.header.serialRef
    let jobArray = jobRef as! [UnownedJob]
    if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *), let taskRef = buffPtr.header.taskRef {
        let taskExecutor = ManagedBufferPointer<UnownedTaskExecutor,Void>(unsafeBufferObject: taskRef).header
        jobArray.forEach{
            $0.runSynchronously(isolatedTo: serials, taskExecutor: taskExecutor)
        }
    } else {
        jobArray.forEach{
            $0.runSynchronously(on: serials)
        }
    }
}

private func tetra_runLoop_schedule_cb(_ state:CFTypeRef, _ runLoop:CFRunLoop, _ mode:CFRunLoopMode) {
//    let buffPtr = ManagedBufferPointer<StateStorage,Void>(unsafeBufferObject: state)
//    let lock = buffPtr.header.lock
//    let _ = buffPtr.header.reference.storeIfNilThenLoad(runLoop)
//    lock.withLockUnchecked {
//        buffPtr.withUnsafeMutablePointerToHeader{
//            if ($0.pointee.registry[runLoop] == nil) {
//                $0.pointee.registry[runLoop] = [mode.rawValue as String]
//            } else {
//                $0.pointee.registry[runLoop]?.insert(mode.rawValue as String)
//            }
//        }
//    }
}

private func tetra_runLoop_cancel_cb(_ state:CFTypeRef, _ runLoop:CFRunLoop, _ mode:CFRunLoopMode) {
//    let buffPtr = ManagedBufferPointer<StateStorage,Void>(unsafeBufferObject: state)
//    let lock = buffPtr.header.lock
//    lock.withLockUnchecked {
//        buffPtr.withUnsafeMutablePointerToHeader{
//            if ($0.pointee.registry[runLoop] != nil) {
//                $0.pointee.registry[runLoop]?.remove(mode.rawValue as String)
//            }
//        }
//    }
}
