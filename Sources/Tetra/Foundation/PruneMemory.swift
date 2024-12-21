//
//  PruneString.swift
//  
//
//  Created by 박병관 on 7/8/24.
//

import Foundation

#if canImport(ObjectiveC)


// since core foundation and objective-c foundation has it's internal optimzation
// it's hard to gurantee if memoryerasing is actullay applied.
// the only way to gurantee is to create mutable memoryerasing instance and fill it
// this method are pretty slow and not even a perfect choice.
// instances created by these methods are guranteed to fill zero to it's owned storage before deallocated.
enum MemoryErasing {
    
    
    // create mutable String which is guarnteed to zero underlying memory when deinitialized
    // this does not erase memory foot print caused by os level memory management such as paging
    // briding to Swift type create implicit copy which does have memory foot print
    static func createMutableString() -> NSMutableString {
        
        return CFStringCreateMutable(Self.allocator, 0)
    }
    
    static func createMutableData() -> NSMutableData {
        
        return CFDataCreateMutable(Self.allocator, 0)
    }
    

    // this Data structure keeps its internal storage shared with Swift runtime
    // so you can cast it to immutable Swift.Data, but do not cast to mutable Data
    static func immutableData<T:DataProtocol>(_ source: T) -> NSData {
        let fastPath = source.withContiguousStorageIfAvailable{
            return if let base = $0.baseAddress, $0.count > 0 {
                CFDataCreate(allocator, base, $0.count)!
            } else {
                Data() as CFData
            }
        }
        if let fastPath {
            return fastPath
        }
        let mutable = CFDataCreateMutable(Self.allocator, 0) as NSMutableData
        for page in source.regions {
            mutable.increaseLength(by: page.count)
            page.withUnsafeBytes{
                if let base = $0.baseAddress, $0.count > 0 {
                    mutable.append(base, length: $0.count)
                }
            }
        }
        return CFDataCreateCopy(allocator, mutable)
    }
    
    static func immutableString<C:Collection,T:UnicodeCodec>(
        decoding source: C,
        as SourceEncoding: T.Type = T.self
    )  -> NSString where C.Element == T.CodeUnit {
        if source.isEmpty {
            return ""
        }
        
        let fastPath = source.withContiguousStorageIfAvailable{
            
            if SourceEncoding == UTF8.self {
                return $0.withMemoryRebound(to: UTF8.CodeUnit.self) { buffer in
                    if buffer.count < 14, buffer.allSatisfy(Unicode.UTF8.isASCII) {
                        return CFStringCreateWithBytes(allocator, buffer.baseAddress!, buffer.count, CFStringBuiltInEncodings.nonLossyASCII.rawValue, false)! as CFString?
                    }
                    return CFStringCreateWithBytes(allocator, buffer.baseAddress!, buffer.count, CFStringBuiltInEncodings.UTF8.rawValue, false)! as CFString?
                }
            }
            if SourceEncoding == UTF16.self {
                return $0.withMemoryRebound(to: UInt8.self) { buffer in
                    CFStringCreateWithBytes(allocator, buffer.baseAddress!, buffer.count, CFStringBuiltInEncodings.UTF16.rawValue, false)! as CFString?

                }
            }
            if SourceEncoding == UTF32.self {
                
                return $0.withMemoryRebound(to: UInt8.self) { buffer in
                    var normal = CFStringCreateWithBytes(allocator, buffer.baseAddress!, buffer.count, CFStringBuiltInEncodings.UTF32LE.rawValue, false)
                    if normal == nil {
                        normal = CFStringCreateWithBytes(allocator, buffer.baseAddress!, buffer.count, CFStringBuiltInEncodings.UTF32.rawValue, false)
                    }
                    return normal
                }
            }
            return nil
        }
        if let fastPath, let fastPath {
            return fastPath
        }
        

        let mutable = CFDataCreateMutable(allocator, 0) as NSMutableData
        let deallocator:CFAllocator
        do {
            var context = CFAllocatorContext()
            context.info = Unmanaged.passUnretained(mutable).toOpaque()
            context.retain = {
                let ptr = Unmanaged<AnyObject>.fromOpaque($0!).retain().toOpaque()
                return .init(ptr)
            }
            context.release = {
                Unmanaged<AnyObject>.fromOpaque($0!).release()
            }
            deallocator = CFAllocatorCreate(nil, &context).takeRetainedValue()
        }
        var encoding:CFStringBuiltInEncodings = .nonLossyASCII
        let _ = transcode(source.makeIterator(), from: SourceEncoding, to: UTF8.self, stoppingOnError: false) { code in
            if !Unicode.ASCII.isASCII(code) {
                encoding = .UTF8
            }
            withUnsafePointer(to: code) {
                CFDataAppendBytes(mutable, $0, 1)
            }
        }
        
       
        let msg = CFStringCreateWithBytesNoCopy(nil, mutable.bytes.assumingMemoryBound(to: UInt8.self), mutable.length, encoding.rawValue, false, deallocator)!
        return msg
    }
    
    
    static func immutableString(_ reduce: (NSMutableString) -> Void) -> NSString {
        let source = CFStringCreateMutable(allocator, 0)! as NSMutableString
        
        reduce(source)
        
        if source.length == 0 {
            // This will return singleton empty string
            return NSString()
        }
        if CFStringGetLength(source) < __kCFStringInlineBufferLength {
            let encoding = CFStringGetFastestEncoding(source)
            if encoding != kCFStringEncodingInvalidId {
                var buffer = CFStringInlineBuffer()
                CFStringInitInlineBuffer(source, &buffer, .init(location: 0, length: CFStringGetLength(source)))
                if encoding == CFStringBuiltInEncodings.ASCII.rawValue {
                    return CFStringCreateWithCString(allocator, buffer.directCStringBuffer, CFStringBuiltInEncodings.nonLossyASCII.rawValue)
                }
                return CFStringCreateWithCString(allocator, buffer.directCStringBuffer, encoding)
            }
        }
        return CFStringCreateCopy(allocator, source)
    }

    
    static func createMutableAttributeString() -> NSMutableAttributedString {
        
        return CFAttributedStringCreateMutable(allocator, 0)
    }
    
    static func immutableAttributeString(
        _ reduce: (NSMutableAttributedString) -> Void
    ) -> NSAttributedString {
        let source = CFAttributedStringCreateMutable(allocator, 0)!
        reduce(source)
        return CFAttributedStringCreateCopy(allocator, source)
    }
    
    static func createUInt16BufferDeallocator(length: Int) -> CFAllocator {
        var context = CFAllocatorContext()
        context.deallocate = { ptr, info in
            guard let ptr else { return }
            let count = Int(bitPattern: info!)
            let base = ptr.assumingMemoryBound(to: UniChar.self)
            let buffer = UnsafeMutableBufferPointer(start: base, count: count)
            buffer.update(repeating: 0)
            buffer.deinitialize().deallocate()
        }
        context.info = .init(bitPattern: length)
        context.copyDescription = { _ in
            .passRetained("NoCopyNSStringDeallocator" as CFString)
        }
        let deallocator = CFAllocatorCreate(nil, &context).takeRetainedValue()
        return deallocator
    }

 
        
    nonisolated(unsafe)
    static let allocator:CFAllocator = {
        var context = CFAllocatorContext()
        context.allocate = { size, hint, _ in
            return malloc(size)
        }
        context.info = nil
        context.retain = nil
        context.release = nil
        context.deallocate = { ptr, _ in
            if let ptr {
                let size = malloc_size(ptr)
                // memset_s ignore compiler optimization
                memset_s(ptr, size, 0, size)
                free(ptr)
            }
        }
        context.copyDescription = { _ in
            return .passRetained("ZeroingCFAllocator" as CFString)
        }
        context.preferredSize = { size, flag, _ in
            return malloc_good_size(size)
        }
        context.reallocate = { ptr, newSize, flag, _ in
            guard let ptr, newSize > 0 else {
                return nil
            }
            let old_size = malloc_size(ptr)
            if old_size > newSize {
                let diff = old_size - newSize
                memset(ptr.advanced(by: newSize), 0, diff)
            }
            return realloc(ptr, newSize)
        }
  
        let allocatorRef = CFAllocatorCreate(nil, &context)
        return allocatorRef!.takeRetainedValue()
    }()
    
    
    
    
}

#else

@available(*, unavailable)
enum MemoryErasing {
    
    
}

#endif
