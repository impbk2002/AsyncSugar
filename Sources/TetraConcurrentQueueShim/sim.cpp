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
//#undef __APPLE__

struct CFQueueTrait: moodycamel::ConcurrentQueueDefaultTraits {
    CF_INLINE void* malloc(size_t size) {
        return CFAllocatorAllocate(kCFAllocatorDefault, size, 0);
    }
    
    CF_INLINE void free(void *ptr) {
        return CFAllocatorDeallocate(kCFAllocatorDefault, ptr);
    }
};



typedef std::shared_ptr<const void> CFCppRef;
typedef moodycamel::ConcurrentQueue<CFCppRef, CFQueueTrait> MyConcurrentQueue;


bool enqueue_ref_concurrent_queue(void* queue, CFTypeRef ref) {
    auto q = reinterpret_cast<MyConcurrentQueue *>(queue);
    auto ptr = CFCppRef(CFRetain(ref), CFRelease);
    
    return q->enqueue(std::move(ptr));
}

CFTypeRef dequeue_ref_concurrent_queue(void* queue) {
    auto q = reinterpret_cast<MyConcurrentQueue *>(queue);
    CFCppRef ptr;
    
    if (q->try_dequeue(ptr)) {
        return ptr.get();
    }
    return nullptr;
}

CF_INLINE CFAllocatorContext create_defaultContext(void) {
    CFAllocatorContext context = {
        0,
        (void*)(kCFAllocatorDefault),
        [](CFTypeRef ref) { return ref ? CFRetain(ref) : ref; },
        [](CFTypeRef ref) { ref ? CFRelease(ref) : void(); },
        [](CFTypeRef ref) { return ref ? CFCopyDescription(ref) : nullptr; },
        [](CFIndex allocSize, CFOptionFlags hint, void *info) { return CFAllocatorAllocate(kCFAllocatorDefault, allocSize, hint); },
        [](void *ptr, CFIndex newsize, CFOptionFlags hint, void *info) { return CFAllocatorReallocate(kCFAllocatorDefault, ptr, newsize, hint); },
        [](void *ptr, void *info) { CFAllocatorDeallocate(kCFAllocatorDefault, ptr); },
        [](CFIndex size, CFOptionFlags hint, void *info) { return CFAllocatorGetPreferredSizeForSize(kCFAllocatorDefault, size, hint); }
    };
    return context;
}

CF_INLINE CFDataRef create_wrapped_queue() {
    constexpr std::size_t queueSize = sizeof(MyConcurrentQueue);
    auto queueBuffer = CFQueueTrait::malloc(queueSize);
    CFAllocatorContext context = {};
    context.deallocate = [](void *ptr, void *info) {
        auto q = reinterpret_cast<MyConcurrentQueue *>(ptr);
        const auto count = q->size_approx();
        assert(count == 0);
        q->~ConcurrentQueue();
        CFQueueTrait::free(q);
    };
    auto queue = new (queueBuffer) MyConcurrentQueue();
    CFAllocatorRef deallocator = CFAllocatorCreate(kCFAllocatorDefault, &context);
    CFDataRef queueWrapper = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, reinterpret_cast<const UInt8 *>(queueBuffer), queueSize, deallocator);
    CFRelease(deallocator);
    return queueWrapper;
}

CF_INLINE CFDataRef create_wrapped_token(MyConcurrentQueue& queue) {
    constexpr std::size_t tokenSize = sizeof(moodycamel::ConsumerToken);
    auto tokenBuffer = CFQueueTrait::malloc(tokenSize);
    CFAllocatorContext context = {};
    auto token = new (tokenBuffer) moodycamel::ConsumerToken(queue);
    context.deallocate = [](void *ptr, void *info) {
        auto t = reinterpret_cast<moodycamel::ConsumerToken *>(ptr);
        t->~ConsumerToken();
        CFQueueTrait::free(t);
    };
    CFAllocatorRef deallocator = CFAllocatorCreate(kCFAllocatorDefault, &context);
    CFDataRef tokenWrapper = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, reinterpret_cast<const UInt8 *>(tokenBuffer), tokenSize, deallocator);
    CFRelease(deallocator);
    return tokenWrapper;
}



CFRunLoopSourceRef create_tetra_runLoop_executor(
    CFTypeRef initialState,
    const TetraContextData *tetraContext
) {
    CFDataRef queueWrapper = create_wrapped_queue();
    CFDataRef tokenWrapper = create_wrapped_token(
                                                  *reinterpret_cast<MyConcurrentQueue *>(const_cast<UInt8 *>(CFDataGetBytePtr(queueWrapper)))
                                                  );
    CFDataRef contextStorage = CFDataCreate(kCFAllocatorDefault, (UInt8 *)tetraContext, sizeof(TetraContextData));
    auto registryContext = create_defaultContext();
    registryContext.retain = [](CFTypeRef ref) -> CFTypeRef {
#if __APPLE__
        constexpr size_t size = sizeof(os_unfair_lock_s);
#else
        constexpr size_t size = sizeof(std::mutex);
#endif
        auto buffer = CFAllocatorAllocate(kCFAllocatorDefault, size, 0);
        
#if __APPLE__
        os_unfair_lock_t mutex = new (buffer) os_unfair_lock_s(OS_UNFAIR_LOCK_INIT);
#else
        auto mutex = new (buffer) std::mutex;
#endif
        
        return buffer;
    };
    registryContext.copyDescription = nullptr;
    registryContext.release = [](CFTypeRef ref) {
#if __APPLE__
        auto lock = reinterpret_cast<os_unfair_lock_t>(const_cast<void*>(ref));
        lock->~os_unfair_lock_s();
#else
        auto mutex = reinterpret_cast<std::mutex *>(const_cast<void*>(ref));
        mutex->~mutex();
#endif
        CFAllocatorDeallocate(kCFAllocatorDefault, const_cast<void*>(ref));
    };
    CFAllocatorRef registryDeallocator = CFAllocatorCreate(kCFAllocatorDefault, &registryContext);
    CFMutableDictionaryRef runLoopRegistry = CFDictionaryCreateMutable(registryDeallocator, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, (CFTypeRef []){queueWrapper, tokenWrapper, initialState, contextStorage, runLoopRegistry}, 5, &kCFTypeArrayCallBacks);
    CFRelease(queueWrapper);
    CFRelease(tokenWrapper);
    CFRelease(contextStorage);
    CFRelease(runLoopRegistry);
    CFRelease(registryDeallocator);
//    CFRelease(initialState);
    /**
        [
            queue,
            consumerToken,
            userDefinedState,
            contextCallbackStorage
     ]
     **/
    CFRunLoopSourceContext soureContext = {
        0,
        (void*)array,
        CFRetain,
        CFRelease,
        [](CFTypeRef ref) -> CFStringRef {
            CFArrayRef array = reinterpret_cast<CFArrayRef>(ref);
            CFTypeRef buffer[] = {
                CFStringCreateWithCString(kCFAllocatorDefault, "moody::camel::ConcurrentQueue", kCFStringEncodingUTF8),
                CFStringCreateWithCString(kCFAllocatorDefault, "moody::camel::ConsumerToken", kCFStringEncodingUTF8),
                CFArrayGetValueAtIndex(array, 2),
                CFStringCreateWithCString(kCFAllocatorDefault, "TetraContextStorage", kCFStringEncodingUTF8),
                CFStringCreateWithCString(kCFAllocatorDefault, "RunLoopRegistry", kCFStringEncodingUTF8),
            };
            CFArrayRef temp = CFArrayCreate(kCFAllocatorDefault, buffer, 5, &kCFTypeArrayCallBacks);
            CFStringRef description = CFCopyDescription(temp);
            CFRelease(temp);
            return description;
        },
        CFEqual,
        CFHash,
        [](void * info, CFRunLoopRef runLoop, CFRunLoopMode mode) {
            //schedule
            auto array = static_cast<CFArrayRef>(info);
            CFTypeRef state = CFArrayGetValueAtIndex(array, 2);
            CFDataRef context = (CFDataRef) CFArrayGetValueAtIndex(array, 3);
            auto tetraContext = (TetraContextData *)CFDataGetBytePtr(context);
            CFRunLoopWakeUp(runLoop);
            {
                CFMutableDictionaryRef registry = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(array, 4);
                CFAllocatorContext allocContext = {};
                CFAllocatorGetContext(CFGetAllocator(registry),&allocContext);
#if __APPLE__
                os_unfair_lock_lock((os_unfair_lock_t)allocContext.info);
#else
                std::lock_guard<std::mutex> lock(*(std::mutex *)allocContext.info);
#endif
                CFMutableSetRef set = (CFMutableSetRef)CFDictionaryGetValue(registry, runLoop);
                if (!set) {
                    set = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
                    CFDictionarySetValue(registry, runLoop, set);
                    CFRelease(set);
                }
#if __APPLE__
                os_unfair_lock_unlock((os_unfair_lock_t)allocContext.info);
#endif
                CFSetAddValue(set, mode);
            }
            if (tetraContext->schedule) {
                tetraContext->schedule(state, runLoop, mode);
            }
        },
        [](void * info, CFRunLoopRef runLoop, CFRunLoopMode mode) {
            // cancel
            auto array = static_cast<CFArrayRef>(info);
            CFTypeRef state = CFArrayGetValueAtIndex(array, 2);
            CFTypeRef context = CFArrayGetValueAtIndex(array, 3);
            auto tetraContext = (TetraContextData *)CFDataGetBytePtr((CFDataRef)context);
            CFRunLoopWakeUp(runLoop);
            {
                CFMutableDictionaryRef registry = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(array, 4);
                CFAllocatorContext allocContext = {};
                CFAllocatorGetContext(CFGetAllocator(registry),&allocContext);
#if __APPLE__
                os_unfair_lock_lock((os_unfair_lock_t)allocContext.info);
#else
                std::lock_guard<std::mutex> lock(*(std::mutex *)allocContext.info);
#endif
                CFMutableSetRef set = (CFMutableSetRef)CFDictionaryGetValue(registry, runLoop);

                CFSetRemoveValue(set, mode);

                if (CFSetGetCount(set) == 0) {
                    CFDictionaryRemoveValue(registry, runLoop);
                }
#if __APPLE__
                os_unfair_lock_unlock((os_unfair_lock_t)allocContext.info);
#endif
            }
            if (tetraContext->cancel) {
                tetraContext->cancel(state, runLoop, mode);
            }

        },
        [](void *info) {
            auto array = static_cast<CFArrayRef>(info);
            auto queue = reinterpret_cast<MyConcurrentQueue *>((void *)CFDataGetBytePtr((CFDataRef)CFArrayGetValueAtIndex(array, 0)));
            auto token = reinterpret_cast<moodycamel::ConsumerToken *>((void *)CFDataGetBytePtr((CFDataRef)CFArrayGetValueAtIndex(array, 1)));
            CFTypeRef state = CFArrayGetValueAtIndex(array, 2);
            CFTypeRef context = CFArrayGetValueAtIndex(array, 3);
            auto tetraContext = (TetraContextData *)CFDataGetBytePtr((CFDataRef)context);
            CFMutableArrayRef dequeue = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            constexpr size_t buffer_size = 10;
            CFCppRef result[buffer_size];
            size_t size = 0;
            while ((size = queue->try_dequeue_bulk(*token, result, buffer_size)) > 0) {
                for (int i = 0; i < size; i++) {
                    CFCppRef ref = std::move(result[i]);
                    CFArrayAppendValue(dequeue, ref.get());
                }
            }
            tetraContext->perform(state, dequeue);
            CFRelease(dequeue);
        }
    };
    
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &soureContext);
    CFRelease(array);
    return source;
}

CFDictionaryRef copy_tetra_runLoop_registry(CFRunLoopSourceRef source) {
    CFMutableDictionaryRef registry_source;
    CFDictionaryRef registry;
    {
        CFRunLoopSourceContext context = {};
        CFRunLoopSourceGetContext(source, &context);
        CFArrayRef array = reinterpret_cast<CFArrayRef>(context.info);
        assert(CFGetTypeID(array) == CFArrayGetTypeID());
        CFTypeRef ref = CFArrayGetValueAtIndex(array, 4);
//        assert(CFGetTypeID(registry_source) == CFDictionaryGetTypeID());
        registry_source = reinterpret_cast<CFMutableDictionaryRef>(const_cast<void*>(ref));
    }
    {
        CFAllocatorContext allocContext = {};
        CFAllocatorGetContext(CFGetAllocator(registry_source),&allocContext);
#if __APPLE__
        os_unfair_lock_lock((os_unfair_lock_t)allocContext.info);
#else
        std::lock_guard<std::mutex> lock(*(std::mutex *)allocContext.info);
#endif
        registry = CFDictionaryCreateCopy(kCFAllocatorDefault, registry_source);
#if __APPLE__
        os_unfair_lock_unlock((os_unfair_lock_t)allocContext.info);
#endif
    }
    return registry;
}

bool tetra_enqueue_and_signal(CFRunLoopSourceRef source, CFTypeRef ref) {
    CFArrayRef array;
    MyConcurrentQueue* queue;
    {
        CFRunLoopSourceContext context = {};
        CFRunLoopSourceGetContext(source, &context);
        array = static_cast<CFArrayRef>(context.info);
    }
    {
        CFDataRef queueWrapper = (CFDataRef)CFArrayGetValueAtIndex(array, 0);
        queue = reinterpret_cast<MyConcurrentQueue *>(const_cast<UInt8 *>(CFDataGetBytePtr(queueWrapper)));
    }
    auto ptr = CFCppRef(CFRetain(ref), CFRelease);
    const bool success = queue->enqueue(std::move(ptr));
    if (!success) {
        return false;
    }
    CFRunLoopSourceSignal(source);
    CFDictionaryRef registry = copy_tetra_runLoop_registry(source);
    CFDictionaryApplyFunction(registry, [](CFTypeRef key, CFTypeRef value, void * info) {
        CFRunLoopWakeUp((CFRunLoopRef) key);
    }, nullptr);
    CFRelease(registry);
    return true;
}
