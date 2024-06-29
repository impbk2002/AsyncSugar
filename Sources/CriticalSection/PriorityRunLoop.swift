//
//  PriorityRunLoop.swift
//  
//
//  Created by 박병관 on 6/29/24.
//

import Atomics
import HeapModule
import CoreFoundation

extension LockFreeQueue: @unchecked Sendable where Element: Sendable {}
final class LockFreeQueue<Element:~Copyable> {
    
    final class Node: AtomicReference {
        let next: ManagedAtomic<Node?>
        var value: Element?
        
        init(value: consuming Element?, next: Node?) {
            self.value = value
            self.next = ManagedAtomic(next)
        }
        
        deinit {
            var values = 0
            // Prevent stack overflow when reclaiming a long queue
            var node = self.next.exchange(nil, ordering: .relaxed)
            while node != nil && isKnownUniquelyReferenced(&node) {
                let next = node!.next.exchange(nil, ordering: .relaxed)
                withExtendedLifetime(node) {
                    values += 1
                }
                node = next
            }
            if values > 0 {
                print(values)
            }
        }
    }
    
    let head: ManagedAtomic<Node>
    let tail: ManagedAtomic<Node>
    
    // Used to distinguish removed nodes from active nodes with a nil `next`.
    let marker = Node(value: nil, next: nil)
    private let counter = UnsafeAtomic<Int>.create(0)
    
    let sanityCheck = ManagedAtomic(false)
    
    init() {
        let dummy = Node(value: nil, next: nil)
        self.head = ManagedAtomic(dummy)
        self.tail = ManagedAtomic(dummy)
        
    }
    
    deinit {
        counter.destroy()
        
    }
    
    func enqueue(_ newValue: consuming Element) {
        if sanityCheck.load(ordering: .acquiring) {
            preconditionFailure("queue is want's to be closed")
        }
        let new = Node(value: newValue, next: nil)
        var tail = self.tail.load(ordering: .acquiring)
        while true {
            let next = tail.next.load(ordering: .acquiring)
            if tail === marker || next === marker {
                // The node we loaded has been unlinked by a dequeue on another thread.
                // Try again.
                tail = self.tail.load(ordering: .acquiring)
                DispatchQueue.global().async {
                    print("enqueue","contention", "1")
                }
                continue
            }
            if let next = next {
                // Assist competing threads by nudging `self.tail` forward a step.
                let (exchanged, original) = self.tail.compareExchange(
                    expected: tail,
                    desired: next,
                    ordering: .acquiringAndReleasing)
                tail = (exchanged ? next : original)
                DispatchQueue.global().async {
                    print("enqueue","contention", "2")
                }               
                continue
            }
            let (exchanged, current) = tail.next.compareExchange(
                expected: nil,
                desired: new,
                ordering: .acquiringAndReleasing
            )
            if exchanged {
                _ = self.tail.compareExchange(expected: tail, desired: new, ordering: .releasing)
                counter.wrappingIncrement(ordering: .releasing)
                return
            }
            DispatchQueue.global().async {
                print("enqueue","contention", "3")
            }
            tail = current!
        }
    }
    
    func dequeue() -> Element? {
        while true {
            let head = self.head.load(ordering: .acquiring)
            let next = head.next.load(ordering: .acquiring)
            if next === marker {
                DispatchQueue.global().async {
                    print("dequeue","contention", "1")
                }
//                print("dequeue", "contention", 1)
                continue
            }
            guard let n = next else { return nil }
            let tail = self.tail.load(ordering: .acquiring)
            if head === tail {
                // Nudge `tail` forward a step to make sure it doesn't fall off the
                // list when we unlink this node.
                _ = self.tail.compareExchange(expected: tail, desired: n, ordering: .acquiringAndReleasing)
            }
            if self.head.compareExchange(expected: head, desired: n, ordering: .releasing).exchanged {
                var result:Element? = nil
                swap(&result, &n.value)
                // To prevent threads that are suspended in `enqueue`/`dequeue` from
                // holding onto arbitrarily long chains of removed nodes, we unlink
                // removed nodes by replacing their `next` value with the special
                // `marker`.
                head.next.store(marker, ordering: .releasing)
                counter.wrappingDecrement(ordering: .releasing)
                return result
            }
            DispatchQueue.global().async {
                print("dequeue","contention", "2")
            }
//            print("dequeue", "contention", 2)

        }
    }
    
    func estimatedLength() -> Int {
        counter.load(ordering: .acquiring)
    }
    
 
 
    
}
import Foundation

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct ExecutorJobContext: ~Copyable {
    
    let job:ExecutorJob
    let executor:UnownedSerialExecutor
    
    consuming func consume() -> ExecutorJob {
        return job
    }
    
}

struct C333<T:AnyObject> {
    
    
    weak var c:T? = nil
}


@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
package
final class RunLoopPriorityExecutor: SerialExecutor {
    
    struct ExecutorContext: Sendable {
        
        let queue:LockFreeQueue<ExecutorJobContext>
        nonisolated(unsafe)
        let source:CFRunLoopSource
        
    }
//    static
    @TaskLocal
    static let myLocal: ExecutorContext? = nil
    
    private let queue:LockFreeQueue<ExecutorJobContext>
    private let sourceRef:RunLoopSourceRef
    private let owned:Bool
    
    nonisolated(unsafe)
    private let runloop:RunLoop

    internal
    init() {

        let existing = Self.myLocal
        self.queue = existing?.queue ?? .init()
        self.runloop = .current
        self.owned = true
        if let source = existing?.source {
            var context = CFRunLoopSourceContext()
            CFRunLoopSourceGetContext(source, &context)
            let info = context.info!
            self.sourceRef = Unmanaged<RunLoopSourceRef>.fromOpaque(info).takeUnretainedValue()
        } else {
            self.sourceRef = .init(ref: queue, nested: false)
        }
    }
    
    internal
    init(nested:()) {
        let existing = Self.myLocal
        self.queue = existing?.queue ?? .init()
        self.runloop = .current
        self.owned = false
        self.sourceRef = .init(null: ())

//        if runloop == .main {
//            self.sourceRef = .init(null: ())
//        } else {
//            self.sourceRef = .init(ref: queue, nested: true)
//            CFRunLoopAddSource(runloop.getCFRunLoop(), sourceRef.source, .commonModes)
//        }
        
    }
    
    private init(
        queue:LockFreeQueue<ExecutorJobContext>,
        runLoop:RunLoop
    ) {
        self.queue = queue
        self.runloop = runLoop
        self.owned = true
        self.sourceRef = .init(null: ())
    }
    
    package
    func enqueue(_ job: consuming ExecutorJob) {
        if runloop == .main {
            MainActor.shared.enqueue(UnownedJob(job))
            return
        }
        if !owned {
            let jobRef = UnownedJob(job)
            let executorRef = asUnownedSerialExecutor()
            runloop.perform {
                jobRef.runSynchronously(on: executorRef)
            }
            return
        }
        queue.enqueue(.init(job: job, executor: asUnownedSerialExecutor()))
        CFRunLoopSourceSignal(sourceRef.source)
        CFRunLoopWakeUp(runloop.getCFRunLoop())
    }
    
    package
    func checkIsolated() {
        precondition(runloop == .current)
    }
    
    var inRunLoop: Bool {
        runloop == .current
    }
    
    package
    func isSameExclusiveExecutionContext(other: RunLoopPriorityExecutor) -> Bool {
        return runloop == other.runloop
    }
    
    package
    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        if runloop == .main {
            return MainActor.sharedUnownedExecutor
        } else {
            return .init(complexEquality: self)
        }
    }
    
    func makeContext() -> ExecutorContext {
        .init(queue: queue, source: sourceRef.source)
    }

    // This is the main of runloop thread
    //ExecutorContext contains JobQueue and RunLoopSource
    static func controlRunLoop(context:ExecutorContext) {
        guard Self.myLocal == nil,
              RunLoop.current.currentMode == nil,
              RunLoop.current != RunLoop.main
        else { return }
        defer {
            while true {
                let (exchanged, _ ) = context.queue.sanityCheck.compareExchange(expected: false, desired: true, ordering: .releasing)
                if exchanged {
                    break
                }
            }
            // last safety check
            Self.$myLocal.withValue(context) {
                Self.processEvents()
            }
        }
        Self.$myLocal.withValue(context) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), context.source, .commonModes)
            while CFRunLoopSourceIsValid(context.source) {
                let passed = RunLoop.current.run(mode: .default, before: .distantFuture)
                if !passed {
                    break
                }
            }
        }

    }
    
    static func pump(
        queue:LockFreeQueue<ExecutorJobContext>
    ) {
        let estimatedCap = queue.estimatedLength()
        var buffer = Heap<JobBlock>(minimumCapacity: estimatedCap)
        buffer.reserveCapacity(estimatedCap)
        print("pump and nil", Self.myLocal == nil)
        var id:UInt64 = .max
        while let block = queue.dequeue() {
            defer { id -= 1 }
            let ref = JobBlock(id: id, job: block)
            buffer.insert(ref)
        }
        while let job = buffer.popMax() {
            job.jobImp.runSynchronously(on: job.executor)
        }

    }
    
    static func processEvents() {
        if let queue = Self.myLocal?.queue {
            pump(queue: queue)
        }
        
    }
    
}

import os

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class RunLoopSourceRef: @unchecked Sendable {
    
    private(set) var source:CFRunLoopSource!
    let queue:LockFreeQueue<ExecutorJobContext>!
    
    init(null:()) {
        self.source = nil
        self.queue = nil
    }
    
    init(ref: LockFreeQueue<ExecutorJobContext>, nested:Bool) {
        if nested {
            queue = ref
        } else {
            queue = nil
        }
        var context = CFRunLoopSourceContext()
        context.version = 0
        context.info = Unmanaged.passUnretained(self).toOpaque()
        if nested {
            context.perform = {
                let ref: RunLoopSourceRef = Unmanaged.fromOpaque($0!).takeUnretainedValue()
                RunLoopPriorityExecutor.pump(queue: ref.queue)
            }
            context.cancel = { info, runLoop, mode in
                let ref: RunLoopSourceRef = Unmanaged.fromOpaque(info!).takeUnretainedValue()
                if let runLoop {
                    CFRunLoopStop(runLoop)
                }
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                    RunLoopPriorityExecutor.pump(queue: ref.queue)
                }
            }
        } else {
            context.cancel = { info, runLoop, mode in
                if let runLoop {
                    CFRunLoopStop(runLoop)
                }
            }
            context.perform = { _ in
                RunLoopPriorityExecutor.processEvents()
            }
        }

        context.copyDescription = { _ in
            let description = "RunLoopPriorityExecutor-Source"
            return .passRetained(description as CFString)
        }
        self.source = CFRunLoopSourceCreate(nil, 0, &context)
    }
    
    
    deinit {
        if let source {
            CFRunLoopSourceInvalidate(source)
        }
    }
    
}


/// Transform current Thread as the RunLoop Executor, and run the runLoop
///
///
/// Actual behavior depends on the current RunLoop state.
///
/// 1) called from existing `RunLoopPriorityExecutor` thread.
///     new executor is connected to the cached component and return, executor lifetime is shared with previous executor.
///     This does not runs runloop. RunLoop is deactivated when this, and all previous executor is dead.
/// 2) called from `MainThread`
///     create dummy executor and return. Dummy executor dispatch all the jobs to the `MainActor`
/// 3) called from active runloop Thread. (someone is already controlling the RunLoop)
///     create unoptimized executor and return. This executor does not controls the runLoop. Existing RunLoop owner has the resposibility to keep runLoop alive, otherwise  enqued Job would leak.
///     This executor does not support JobPriority. And simply create NSObject and schedule the block
///
/// 4) called from fresh Thread (no one is running runLoop)
///     create optimized executor, call `setupHandle` than controls the RunLoop of current Thread.
///     This function does not return, until executor is dead. So, `setupHandle` is the entrypoint of using the executor.
///     This executor does recognize priority
/// - Parameter setupHandle: called right before runLoop runs, runloop is active until executor is dead. this block is called exactly once.
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
package
func executeRunloop(
    setupHandle: (RunLoopPriorityExecutor) -> Void
) {
    // if nested -> already running runloop 1) we are controlling the runloop 2) somebody is controlling runloop
    //      1) our executor is already controlling thread and we are calling it at the same thread
    //          -> do not perform any nested run
    //      2) somebody is already taking control of this thread
    // if mainloop -> no-op redirect to mainactor
    // if no-runloop -> controll it!
    guard !Thread.isMainThread else {
        // we don't run main runLoop since MainActor is the way togo
        // `RunLoopPriorityExecutor` redirect every thing back to the MainActor
        setupHandle(RunLoopPriorityExecutor(nested: ()))
        return
    }
    let existing = RunLoopPriorityExecutor.myLocal
    if let existing, CFRunLoopContainsSource(CFRunLoopGetCurrent(), existing.source, .commonModes) {
        // nested runloop which we are taking full control or main runloop
        // connect to the existing task-queue and return
        setupHandle(RunLoopPriorityExecutor.init())
        return
    }
    

    // complex case
    if RunLoop.current.currentMode != nil {
        // we are in the active runloop which someone else is taking the full control
        // nested runloop is not an ideal case
        
        // configure runloop source and attach it maybe?
        // but in that case tasklocal is not visible in same thread ...
        // lets fall back to unoptimized way, stashing every job as Clousre block, ignoring priority
        // this RunLoopExecutor never controls the runloop
        let executor = RunLoopPriorityExecutor(nested: ())
        setupHandle(executor)
        return
    }
    let context:RunLoopPriorityExecutor.ExecutorContext
    do {
        let executor = RunLoopPriorityExecutor()
        context = executor.makeContext()
        setupHandle(consume executor)
    }
    RunLoopPriorityExecutor.controlRunLoop(context: context)
}




struct JobBlock: Hashable, Comparable {
    
    let id:UInt64
    let priority:UInt8
    let jobImp:UnownedJob
    let executor:UnownedSerialExecutor
    
    @available(macOS 14.0, *)
    init(id: UInt64, job: consuming ExecutorJobContext) {
        self.id = id
        self.priority = job.job.priority.rawValue
        self.executor = job.executor
        self.jobImp = UnownedJob(job.job)
        
    }
    
    init(id: UInt64, jobRef: UnownedJob, executor:UnownedSerialExecutor) {
        self.id = id
        self.priority = 0
        self.jobImp = jobRef
        self.executor = executor
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(priority)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.id < rhs.id
        }
        return lhs.priority < rhs.priority
    }
    
    static func > (lhs:Self, rhs:Self) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.id > rhs.id
        }
        return lhs.priority > rhs.priority
    }

}
