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

public final class RunLoopPriorityExecutor {
    
    @usableFromInline
    internal let heaps: some UnfairStateLock<Heap<JobBlock>> = createCheckedStateLock(checkedState: .init())
    
    // cache for faster comparsion, RunLoop comparsion trigger creating extra RunLoop
    // I'm not sure storing pthread_t as bitpattern is a good idea
    @usableFromInline
    let threadId:Int
    
    @usableFromInline
    nonisolated(unsafe)
    internal let looper:RunLoop
   
    @usableFromInline
    internal var cfRef:CFRunLoop {
        looper.getCFRunLoop()
    }
    
    @usableFromInline
    nonisolated(unsafe)
    internal let source:CFRunLoopSource
    

    @inlinable
    internal init() {
        
        let (buffer, source) = Self.sharedSource
        self.looper = .current
        self.threadId = .init(bitPattern: pthread_self())
        self.source = source
        buffer.header = .init(value: self)
        if Thread.isMainThread {
            CFRunLoopSourceInvalidate(source)
            return
        } else {
            CFRunLoopAddSource(cfRef, source, .commonModes)
        }
    }
    
    @inlinable
    deinit {
        let key = ObjectIdentifier(looper)
        let _ = Self.cache.withLockUnchecked{
            $0.removeValue(forKey: key)
        }
        CFRunLoopSourceInvalidate(source)
        if inRunLoop, looper.currentMode != nil {
            var arrays = CFRunLoopCopyAllModes(looper.getCFRunLoop()) as! [CFString]
            arrays.append(CFRunLoopMode.commonModes.rawValue)
            let timer = CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0, nil, nil)
            arrays.forEach{
                CFRunLoopAddTimer(cfRef, timer, .init($0))
            }
        } else {
            CFRunLoopWakeUp(looper.getCFRunLoop())
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
        return looper
    }
    
    @usableFromInline
    nonisolated
    internal func schedule(_ job: consuming UnownedJob) {
        if CFEqual(cfRef, CFRunLoopGetMain()) {
            MainActor.shared.enqueue(job)
            return
        }
        heaps.withLock{ [job] in
            // lastest has the lower id which results lower priority
            let id = -$0.count
            $0.insert(.init(id: id, jobRef: consume job))
        }
        CFRunLoopSourceSignal(source)
        if !inRunLoop {
            CFRunLoopWakeUp(cfRef)
        }
    }
    
    @usableFromInline
    internal func evaluateCommonModes() -> [RunLoop.Mode] {
        var arrys = [String]()
        withUnsafeMutablePointer(to: &arrys) { ptr in
            var context = CFRunLoopSourceContext()
            context.info = .init(ptr)
            context.schedule = { info, _ , mode in
                let arrayPtr = info!.assumingMemoryBound(to: [String].self)
                arrayPtr.pointee.append(mode!.rawValue as String)
            }
            let emptySource = CFRunLoopSourceCreate(nil, 0, &context)!
            CFRunLoopAddSource(cfRef, emptySource, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        return arrys.map{ RunLoop.Mode($0) }
    }
    
    @inlinable
    nonisolated
    public func add(_ mode:RunLoop.Mode) {
        if CFEqual(cfRef, CFRunLoopGetMain()) {
            return
        }
        CFRunLoopAddSource(cfRef, source, .init(mode.rawValue as CFString))
    }
    
    // you can not remove common mode
    @inlinable
    nonisolated
    public func remove(_ mode:RunLoop.Mode) {
        if CFEqual(cfRef, CFRunLoopGetMain()) {
            return
        }
        if mode == .common || mode == .default || evaluateCommonModes().contains(mode) {
            return
        }
        CFRunLoopRemoveSource(cfRef, source, .init(mode.rawValue as CFString))
    }
    
}

extension RunLoopPriorityExecutor: SerialExecutor {
    
    @inlinable
    nonisolated
    public func isSameExclusiveExecutionContext(other: borrowing RunLoopPriorityExecutor) -> Bool {
        return CFEqual(cfRef, other.cfRef)
    }
    
    @inlinable
    nonisolated
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        if CFEqual(cfRef, CFRunLoopGetMain()) {
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
        precondition(CFEqual(cfRef, CFRunLoopGetCurrent()), "Unexpected isolation context, expected to be executing on \(cfRef)")
    }
    
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    @inlinable
    nonisolated
    public func enqueue(_ job: consuming ExecutorJob) {
        schedule(.init(job))
    }
    
    @inlinable
    nonisolated
    public func enqueue(_ job: UnownedJob) {
        schedule(job)
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
    static let cache: some UnfairStateLock<[ObjectIdentifier: Boxed]> = createUncheckedStateLock(uncheckedState: [:])
    
    @usableFromInline
    static var sharedSource:(ManagedBuffer<Boxed,Void>, CFRunLoopSource) {
        let buffer = ManagedBuffer<Boxed, Void>.create(minimumCapacity: 0) { _ in
            return .init(value: nil)
        }
        var context = CFRunLoopSourceContext()
        context.version = 0
        context.info = Unmanaged.passUnretained(buffer).toOpaque()
        context.retain = {
            let ptr = Unmanaged<AnyObject>.fromOpaque($0!).retain().toOpaque()
            return .init(ptr)
        }
        context.release = {
            Unmanaged<AnyObject>.fromOpaque($0!).release()
        }
        context.perform = {
            var heap:Heap<JobBlock>
            let execute:(@Sendable (consuming UnownedJob) ->Void)
            do {
                let boxed = Unmanaged<ManagedBuffer<Boxed,Void>>.fromOpaque($0!)
                    .takeUnretainedValue()
                guard let ref = boxed.header.value else { return }
                heap = ref.heaps.withLock{
                    
                    var old = Heap<JobBlock>()
                    swap(&$0, &old)
                    return old
                }
                let serial = ref.asUnownedSerialExecutor()
                if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                    let task = ref.asUnownedTaskExecutor()
                    execute = { [serial, task] in
                        $0.runSynchronously(isolatedTo: serial, taskExecutor: task)
                    }
                } else {
                    execute = { [serial] in
                        $0.runSynchronously(on: serial)
                    }
                }
            }
            while let block = heap.popMax() {
                execute(block.jobImp)
            }
        }

        context.copyDescription = { null in
            let description = "RunLoopPExecutor"
            return .passRetained(description as CFString)
        }
        return (buffer, CFRunLoopSourceCreate(nil, 0, &context))
    }
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
    public static func getOrCreate(_ block: (consuming Self) -> Void) {
        if Thread.isMainThread {
            let executor = Self()
            (consume block)(executor)
            return
        }
        let runLoop = RunLoop.current
        let key = ObjectIdentifier(runLoop)
        if let existing = cache.withLockUnchecked({
            $0[key]?.value
        }) {
            (consume block)(existing as! Self)
            return
        }
        let source:CFRunLoopSource
        do {
            let executor = Self()
            Self.cache.withLockUnchecked{
                $0[key] = .init(value: executor)
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

