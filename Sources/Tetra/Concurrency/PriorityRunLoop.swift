//
//  PriorityRunLoop2.swift
//  
//
//  Created by 박병관 on 6/30/24.
//

import HeapModule
import Foundation
import CoreFoundation
public import CriticalSection

@usableFromInline
struct RunLoopPriorityQueue: ~Copyable, Sendable {
    
    @usableFromInline
    internal let heaps: some UnfairStateLock<Heap<JobBlock>> = createCheckedStateLock(checkedState: .init())
   
    @usableFromInline
    nonisolated(unsafe)
    internal let runLoop:CFRunLoop
    
    @usableFromInline
    nonisolated(unsafe)
    internal let source:CFRunLoopSource
    
    @usableFromInline
    internal let isMain:Bool
    
    nonisolated(unsafe)
    internal let thread:pthread_t
    
    @usableFromInline
    init(
        runLoop: RunLoop,
        threadId: pthread_t,
        execute: @escaping (consuming UnownedJob) -> Void
    ) {
        self.runLoop = runLoop.getCFRunLoop()
        self.thread = threadId
        self.isMain = CFEqual(runLoop, CFRunLoopGetMain())
        if isMain {
            self.source = CFRunLoopSourceCreate(nil, 0, nil)
            CFRunLoopSourceInvalidate(source)
        } else {
            self.source = RunLoopSourceCreateWithHandler { [heaps] in
                
                guard $0 == .perform else { return }
                
                var queue = heaps.withLock{
                    var next = Heap<JobBlock>()
                    swap(&next, &$0)
                    return next
                }
                while let block = queue.popMax() {
                    defer {
                        if let ref = block.token {
                            pthread_override_qos_class_end_np(ref)
                        }
                    }
                    let job = block.jobImp
                    execute(job)
                }
            }
            CFRunLoopAddSource(self.runLoop, source, .commonModes)
        }
    }
    
    @inlinable
    deinit {
        if isMain {
            return
        }
        CFRunLoopSourceInvalidate(source)
        if CFRunLoopCopyCurrentMode(runLoop) != nil{
            var arrays = CFRunLoopCopyAllModes(runLoop) as! [CFString]
            arrays.append(CFRunLoopMode.commonModes.rawValue)
            let timer = CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0, nil, nil)
            arrays.forEach{
                CFRunLoopAddTimer(runLoop, timer, .init($0))
            }
        } else {
            CFRunLoopWakeUp(runLoop)
        }
        heaps.withLock{
            precondition($0.count == 0)
        }
    }
    
    @usableFromInline
    internal func evaluateCommonModes() -> [CFRunLoopMode] {
        var arrys = [CFRunLoopMode]()
        withUnsafeMutablePointer(to: &arrys) { ptr in
            var context = CFRunLoopSourceContext()
            context.info = .init(ptr)
            context.schedule = { info, _ , mode in
                let arrayPtr = info!.assumingMemoryBound(to: [CFRunLoopMode].self)
                arrayPtr.pointee.append(mode!)
            }
            let emptySource = CFRunLoopSourceCreate(nil, 0, &context)!
            CFRunLoopAddSource(runLoop, emptySource, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        return arrys
    }
    
    
    @usableFromInline
    nonisolated
    internal func schedule(_ job: consuming UnownedJob) {
        if isMain {
            MainActor.shared.enqueue(job)
            return
        }

        let override: pthread_override_t?
        
        if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
            let qos = job.priority.evaluateQos()
            if qos.qosClass == .unspecified {
                override = nil
            } else {
                override = pthread_override_qos_class_start_np(thread, qos.qosClass.rawValue, Int32(qos.relativePriority))
            }
        } else {
            override = nil
        }
        
        
        heaps.withLockUnchecked{ [job] in
            // lastest has the lower id which results lower priority
            let id = -$0.count
            var item = JobBlock(id: id, jobRef: consume job)
            item.token = override
            $0.insert(item)
        }
        CFRunLoopSourceSignal(source)
    }
    
    @inlinable
    nonisolated
    internal func add(_ mode:CFRunLoopMode) {
        if isMain {
            return
        }
        CFRunLoopAddSource(runLoop, source, mode)
    }
    
    // you can not remove common mode
    @inlinable
    nonisolated
    internal func remove(_ mode:CFRunLoopMode) {
        if isMain {
            return
        }
        if mode == .commonModes || mode == .defaultMode || evaluateCommonModes().contains(mode) {
            return
        }
        CFRunLoopRemoveSource(runLoop, source, mode)
    }
    
}


public final class RunLoopPriorityExecutor {
    

    // cache for faster comparsion, RunLoop comparsion trigger creating extra RunLoop
    // I'm not sure storing pthread_t as bitpattern is a good idea
    @usableFromInline
    let threadId:Int
    
    @usableFromInline
    internal let queue:RunLoopPriorityQueue
    
    @usableFromInline
    nonisolated(unsafe)
    internal let _runLoop:RunLoop

    @inlinable
    internal init() {
        self._runLoop = .current
        var serialRef: UnownedSerialExecutor! = nil
        self.threadId = .init(bitPattern: pthread_self())
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            var taskRef:UnownedTaskExecutor! = nil
            self.queue = RunLoopPriorityQueue(runLoop: .current, threadId: pthread_self()) {
                $0.runSynchronously(isolatedTo: serialRef, taskExecutor: taskRef)
            }
            taskRef = asUnownedTaskExecutor()
        } else {
            self.queue = RunLoopPriorityQueue(runLoop: .current, threadId: pthread_self()) {
                $0.runSynchronously(on: serialRef)
            }
        }
        serialRef = asUnownedSerialExecutor()

    }
    
    @inlinable
    deinit {
        let key = ObjectIdentifier(queue.runLoop)
        let _ = Self.cache.withLockUnchecked{
            $0.removeValue(forKey: key)
        }


    }
    
    @inlinable
    nonisolated
    public var inRunLoop: Bool {
        let this = pthread_t(bitPattern: threadId)
        let current = pthread_self()
        let check = pthread_equal(this, current)
        
        return check != 0
    }
    
    // if you access the runLoop while not isolated, it will trigger assert
    @inlinable
    public var runLoop: RunLoop {
        assert(inRunLoop, "can not access \(#function) outside of isolation")
        return _runLoop
    }

    @inlinable
    nonisolated
    public func add(_ mode:RunLoop.Mode) {
        queue.add(.init(mode.rawValue as CFString))
    }
    
    // you can not remove common mode
    @inlinable
    nonisolated
    public func remove(_ mode:RunLoop.Mode) {
        queue.remove(.init(mode.rawValue as CFString))
    }
    
    @usableFromInline
    internal var source:CFRunLoopSource {
        queue.source
    }
    
}

extension RunLoopPriorityExecutor: SerialExecutor {
    
    @inlinable
    nonisolated
    public func isSameExclusiveExecutionContext(other: borrowing RunLoopPriorityExecutor) -> Bool {
        return CFEqual(queue.runLoop, other.queue.runLoop)
    }
    
    @inlinable
    nonisolated
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        if queue.isMain {
            return MainActor.sharedUnownedExecutor
        } else if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
            return .init(complexEquality: self)
        } else {
            return .init(ordinary: self)
        }
    }
    
    @inlinable
    nonisolated
    public func checkIsolated() {
        precondition(CFEqual(queue.runLoop, CFRunLoopGetCurrent()), "Unexpected isolation context, expected to be executing on \(runLoop)")
    }
    
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    @inlinable
    nonisolated
    public func enqueue(_ job: consuming ExecutorJob) {
        queue.schedule(.init(job))
        
        if !inRunLoop {
            CFRunLoopWakeUp(queue.runLoop)
        }
    }
    
    @inlinable
    nonisolated
    public func enqueue(_ job: UnownedJob) {
        queue.schedule(job)
        if !inRunLoop {
            CFRunLoopWakeUp(queue.runLoop)
        }
    }
    
}

// MARK: Concurrency TaskExecutor
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension RunLoopPriorityExecutor: TaskExecutor { }


extension RunLoopPriorityExecutor {
    
    @usableFromInline
    struct Boxed {
        @usableFromInline
        unowned let value:RunLoopPriorityExecutor?
        
        @usableFromInline
        init(value: RunLoopPriorityExecutor?) {
            self.value = value
        }
        
    }
    
    // we rarely access this state, only when creating and deinitialzing
    // so it is reasonable to use global lock rather than thread local
    // since thread local keeps stored reference alive and
    // user can call this method from thread pool( Concurrency, libdispatch)
    @usableFromInline
    static let cache: some UnfairStateLock<[ObjectIdentifier: Unmanaged<RunLoopPriorityExecutor>]> = createUncheckedStateLock(uncheckedState: [:])
    
 
}

extension RunLoopPriorityExecutor {
    
    
    /// Transform current Thread as the RunLoop Executor, and run the runLoop
    ///
    ///
    /// Actual behavior depends on the current RunLoop state.
    ///
    /// 1) called from existing `RunLoopPriorityExecutor` thread.
    ///     existing Executor is returned
    ///     This does not runs runloop. RunLoop is deactivated when this, and all previous executor is dead.
    /// 2) called from `MainThread`
    ///     create dummy executor and return. Dummy executor dispatch all the jobs to the `MainActor`
    /// 3) called from active runloop Thread. (someone is already controlling the RunLoop)
    ///     create executor and return. This executor does not controls the runLoop. Existing RunLoop owner has the resposibility to keep runLoop alive, otherwise  enqued Job would leak.
    ///
    /// 4) called from fresh Thread (no one is running runLoop)
    ///     create optimized executor, call `setupHandle` than controls the RunLoop of current Thread.
    ///     This function does not return, until executor is dead. So,`setupHandle` is the entrypoint of using the executor.
    /// - Parameter setupHandle: called right before runLoop runs, runloop is active until executor is dead. this block is called exactly once.
    /// - Important: when using it with existing active runLoop, keep runloop alive until Executor is gracefully deinitialized
    @inlinable
    public static func getOrCreate(_ block: (consuming RunLoopPriorityExecutor) -> Void) {
        if Thread.isMainThread {
            let executor = Self()
            (consume block)(executor)
            return
        }
        let runLoop = RunLoop.current.getCFRunLoop()
        let key = ObjectIdentifier(runLoop)
        if let existing = cache.withLock({
            $0[key]?.takeUnretainedValue()
        }) {
            (consume block)(existing)
            return
        }
        let source:CFRunLoopSource
        do {
            let executor = Self()
            Self.cache.withLock{
                $0[key] = .passUnretained(executor)
            }
            source = executor.source
            (consume block)(executor)
        }
        while CFRunLoopSourceIsValid(source), RunLoop.current.run(mode: .default, before: .distantFuture) {
            
        }
    }
    
    
}






/*
 
 Executor -> contains runLoop and Context
 Context has JobQueue
 One or More Executor can reference the same Context And RunLoop
 if Executor reference the same RunLoop than the Context also must be smae
 Context has connection to RunLoop Source and Observer
 Context owns the Source and Observer,
 Source has no info about the context
 Observer has a weak reference to the Context
 when Context is destroyed (no executor is alived), it stops the Source, but do not destroy RunLoop Observer
 RunLoopObserver it self checks the weak reference of Context and do its clean up
 
 thread_local -> store
 
 
 
 
 */


