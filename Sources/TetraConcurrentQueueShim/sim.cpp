//
//  sim.m
//  Tetra
//
//  Created by 박병관 on 1/20/25.
//

#define MOODYCAMEL_NO_THREAD_LOCAL
#include "concurrentqueue.h"
#include "sim.h"
#include <assert.h>
#if __APPLE__
#include <os/lock.h>
#endif

struct CFQueueTrait: moodycamel::ConcurrentQueueDefaultTraits {
    CF_INLINE void* malloc(size_t size) {
        return CFAllocatorAllocate(kCFAllocatorDefault, size, 0);
    }
    
    CF_INLINE void free(void *ptr) {
        return CFAllocatorDeallocate(kCFAllocatorDefault, ptr);
    }
};


//#undef __APPLE__
typedef std::shared_ptr<const void> CFCppRef;
typedef moodycamel::ConcurrentQueue<CFCppRef, CFQueueTrait> MyConcurrentQueue;

typedef struct {
    MyConcurrentQueue queue;
    moodycamel::ConsumerToken token;
    TetraContextData context;
    CFTypeRef state;
    CFMutableDictionaryRef runLoopRegistry;
#if __APPLE__
    os_unfair_lock_s lock;
#else
    std::mutex* lock;
#endif
    
} RunLoopContextInfo;

CFRunLoopSourceRef create_tetra_runLoop_executor(
    CFTypeRef initialState,
    const TetraContextData *tetraContext
) {
    auto queue = MyConcurrentQueue();
    auto token = moodycamel::ConsumerToken(queue);
    
    RunLoopContextInfo stackInfo = RunLoopContextInfo{
        std::move(queue),
        std::move(token),
        *tetraContext,
        initialState,
        CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks),
#if __APPLE__
        OS_UNFAIR_LOCK_INIT,
#else
        new (CFQueueTrait::malloc(sizeof(std::mutex))) std::mutex(),
#endif
    };
    CFRunLoopSourceContext soureContext = {
        0,
        (void*)&stackInfo,
        [](const void * stackRawInfo) -> const void * {
            void * buffer = CFAllocatorAllocate(kCFAllocatorDefault, sizeof(RunLoopContextInfo), 0);
            RunLoopContextInfo* stackInfo = reinterpret_cast<RunLoopContextInfo*>(const_cast<void*>(stackRawInfo));
            
            auto myInfo = new (buffer) RunLoopContextInfo(std::move(*stackInfo));
            myInfo->state = CFRetain(stackInfo->state);
            return myInfo;
        },
        [](const void * heapRawInfo) {
            auto info = reinterpret_cast<RunLoopContextInfo*>(const_cast<void*>(heapRawInfo));
#if !__APPLE__
            info->lock->~mutex();
            CFQueueTrait::free(info->lock);
#endif
            auto stack = std::move(*info);
            CFAllocatorDeallocate(kCFAllocatorDefault, info);
            CFRelease(stack.runLoopRegistry);
            CFRelease(stack.state);
        },
        nullptr,
        nullptr,
        nullptr,
        [](void * info, CFRunLoopRef runLoop, CFRunLoopMode mode) {
            //schedule
            auto &sourceInfo = *reinterpret_cast<RunLoopContextInfo *>(info);
            CFRunLoopWakeUp(runLoop);
            {
                CFMutableDictionaryRef registry = sourceInfo.runLoopRegistry;
#if __APPLE__
                os_unfair_lock_lock(&sourceInfo.lock);
#else
                std::lock_guard<std::mutex> lock(*sourceInfo.lock);
#endif
                CFMutableSetRef set = (CFMutableSetRef)CFDictionaryGetValue(registry, runLoop);
                if (!set) {
                    set = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
                    CFDictionarySetValue(registry, runLoop, set);
                    CFRelease(set);
                }
#if __APPLE__
                os_unfair_lock_unlock(&sourceInfo.lock);
#endif
                CFSetAddValue(set, mode);
            }
            if (sourceInfo.context.schedule) {
                sourceInfo.context.schedule(sourceInfo.state, runLoop, mode);
            }
        },
        [](void * info, CFRunLoopRef runLoop, CFRunLoopMode mode) {
            // cancel
            auto &sourceInfo = *reinterpret_cast<RunLoopContextInfo *>(info);
            CFRunLoopWakeUp(runLoop);
            {
                CFMutableDictionaryRef registry = sourceInfo.runLoopRegistry;
#if __APPLE__
                os_unfair_lock_lock(&sourceInfo.lock);
#else
                std::lock_guard<std::mutex> lock(*sourceInfo.lock);
#endif
                CFMutableSetRef set = (CFMutableSetRef)CFDictionaryGetValue(registry, runLoop);

                CFSetRemoveValue(set, mode);

                if (CFSetGetCount(set) == 0) {
                    CFDictionaryRemoveValue(registry, runLoop);
                }
#if __APPLE__
                os_unfair_lock_unlock(&sourceInfo.lock);
#endif
            }
            if (sourceInfo.context.schedule) {
                sourceInfo.context.schedule(sourceInfo.state, runLoop, mode);
            }

        },
        [](void *info) {
            auto &sourceInfo = *reinterpret_cast<RunLoopContextInfo *>(info);
            

            CFMutableArrayRef dequeue = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            constexpr size_t buffer_size = 10;
            CFCppRef result[buffer_size];
            size_t size = 0;
            while ((size = sourceInfo.queue.try_dequeue_bulk(sourceInfo.token, result, buffer_size)) > 0) {
                for (int i = 0; i < size; i++) {
                    CFCppRef ref = std::move(result[i]);
                    CFArrayAppendValue(dequeue, ref.get());
                }
            }
            sourceInfo.context.perform(sourceInfo.state, dequeue);
            CFRelease(dequeue);
        }
    };
    
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &soureContext);
    return source;
}

CFDictionaryRef copy_tetra_runLoop_registry(CFRunLoopSourceRef source) {
    RunLoopContextInfo* info;
    {
        CFRunLoopSourceContext context = {};
        CFRunLoopSourceGetContext(source, &context);
        info = reinterpret_cast<RunLoopContextInfo *>(context.info);
    }
    RunLoopContextInfo& variable = *info;
    CFDictionaryRef registry;
    {
#if __APPLE__
        os_unfair_lock_lock(&variable.lock);
#else
        std::lock_guard<std::mutex> lock(*variable.lock);
#endif
        registry = CFDictionaryCreateCopy(kCFAllocatorDefault, variable.runLoopRegistry);
#if __APPLE__
        os_unfair_lock_unlock(&variable.lock);
#endif
    }
    return registry;
}

CF_INLINE CFDictionaryRef try_copy_tetra_runLoop_registry(CFRunLoopSourceRef source) {
    RunLoopContextInfo* info;
    {
        CFRunLoopSourceContext context = {};
        CFRunLoopSourceGetContext(source, &context);
        info = reinterpret_cast<RunLoopContextInfo *>(context.info);
    }
    RunLoopContextInfo& variable = *info;
    CFDictionaryRef registry;
    {
#if __APPLE__
        if (os_unfair_lock_trylock(&variable.lock) == false) {
            return nullptr;
        }
#else
        std::unique_lock<std::mutex> lock(*variable.lock, std::try_to_lock);
        if(!lock.owns_lock()){
            return nullptr;
        }
#endif
        registry = CFDictionaryCreateCopy(kCFAllocatorDefault, variable.runLoopRegistry);
#if __APPLE__
        os_unfair_lock_unlock(&variable.lock);
#endif
    }
    return registry;
}


bool tetra_enqueue_and_signal(CFRunLoopSourceRef source, CFTypeRef ref) {
    RunLoopContextInfo* info;
    {
        CFRunLoopSourceContext context = {};
        CFRunLoopSourceGetContext(source, &context);
        info = reinterpret_cast<RunLoopContextInfo *>(context.info);
    }
    RunLoopContextInfo& variable = *info;
    auto ptr = CFCppRef(CFRetain(ref), CFRelease);
    const bool success = variable.queue.enqueue(std::move(ptr));
    if (!success) {
        return false;
    }
    CFRunLoopSourceSignal(source);
    CFDictionaryRef registry = try_copy_tetra_runLoop_registry(source);
    // somebody is already waking up the runloop
    if (registry == nullptr) {
        
        return true;
    }
    CFDictionaryApplyFunction(registry, [](CFTypeRef key, CFTypeRef value, void * info) {
        if (CFRunLoopIsWaiting((CFRunLoopRef) key)) {
            CFRunLoopWakeUp((CFRunLoopRef) key);
        }
    }, nullptr);
    CFRelease(registry);
    return true;
}

CFTypeRef tetra_get_stateInfo(CFRunLoopSourceRef source) {
    RunLoopContextInfo* info;
    {
        CFRunLoopSourceContext context = {};
        CFRunLoopSourceGetContext(source, &context);
        info = reinterpret_cast<RunLoopContextInfo *>(context.info);
    }
    return info->state;
}
