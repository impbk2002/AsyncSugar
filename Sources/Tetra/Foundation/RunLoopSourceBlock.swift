//
//  RunLoopSourceBlock.swift
//  
//
//  Created by 박병관 on 7/6/24.
//
import CoreFoundation

@usableFromInline
enum RunLoopSourceEvent: Hashable {
    
    case perform
    case schedule(CFRunLoop, CFRunLoopMode)
    case cancel(CFRunLoop, CFRunLoopMode)
}


/// This creates Block based version 0 CFRunLoopSource
/// - Parameters:
///   - allocator: pass `nil` unless you have a reason for it
///   - order: pass `0` unless you have a reason for it
///   - block: RunLoopSource Event handler,  this callbacked called in serial, and never called concurrently
/// - Returns: this block based `CFRunLoopSource`
@usableFromInline
func RunLoopSourceCreateWithHandler(
    _ allocator: CFAllocator? = nil,
    _ order: CFIndex = 0,
    _ block: @escaping (RunLoopSourceEvent) -> ()
) -> CFRunLoopSource {
    typealias BlockSourceType = @convention(block) (CFRunLoop?, CFRunLoopMode?, UnsafePointer<Bool>?) -> Void
    let cBlock: BlockSourceType = {
        switch $2?.pointee {
        case .none:
            block(.perform)
        case .some(true):
            block(.schedule($0!, $1!))
        case .some(false):
            block(.cancel($0!, $1!))
        }
    }
    let ref = cBlock as AnyObject
    let info = Unmanaged<AnyObject>.passUnretained(ref).toOpaque()
    var sourceContext = CFRunLoopSourceContext()
    sourceContext.perform = { info in
        let ref = Unmanaged<AnyObject>.fromOpaque(info!).takeUnretainedValue()
        
        let block = unsafeBitCast(ref, to: BlockSourceType.self)
        block(nil, nil, nil)
    }
    sourceContext.schedule = { info, runLoop, mode in
        let ref = Unmanaged<AnyObject>.fromOpaque(info!).takeUnretainedValue()
        let block = unsafeBitCast(ref, to: BlockSourceType.self)
        withUnsafePointer(to: true) {
            block(runLoop, mode, $0)
        }
    }
    sourceContext.cancel = { info, runLoop, mode in
        let ref = Unmanaged<AnyObject>.fromOpaque(info!).takeUnretainedValue()
        let block = unsafeBitCast(ref, to: BlockSourceType.self)
        withUnsafePointer(to: false) {
            block(runLoop, mode, $0)
        }
    }
    sourceContext.hash = nil
    sourceContext.equal = nil
    sourceContext.copyDescription = { info in
        if let info {
            let address = UInt(bitPattern: info)
            let hex = String(address, radix: 16)
            return .passRetained("RunLoopSourceCreateWithHandler (0x\(hex))" as CFString)
        } else {
            return .passRetained("RunLoopSourceCreateWithHandler" as CFString)
        }
    }
    sourceContext.version = 0
    sourceContext.release = {
        Unmanaged<AnyObject>.fromOpaque($0!).release()
    }
    sourceContext.retain = {
        .init(Unmanaged<AnyObject>.fromOpaque($0!).retain().toOpaque())
    }
    sourceContext.info = info
    let source = CFRunLoopSourceCreate(allocator, order, &sourceContext)!
    return source
}
