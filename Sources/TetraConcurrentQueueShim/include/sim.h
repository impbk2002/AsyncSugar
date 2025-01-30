//
//  Header.h
//  Tetra
//
//  Created by 박병관 on 1/20/25.
//

#ifndef ConcurrentQueue_shim_h
#define ConcurrentQueue_shim_h
//#include <memory>
//#include "concurrentqueue.hpp"
#include <swift/bridging>
#include <CoreFoundation/CoreFoundation.h>


CF_ASSUME_NONNULL_BEGIN

typedef struct  {
    void(*perform)(CFTypeRef state, CFArrayRef job);
    void(* _Nullable schedule)(CFTypeRef state, CFRunLoopRef rl, CFRunLoopMode mode);
    void(* _Nullable cancel)(CFTypeRef state, CFRunLoopRef rl, CFRunLoopMode mode);
} TetraContextData;

//class
//SWIFT_NONCOPYABLE
//SWIFT_SHARED_REFERENCE(retainSharedObject, releaseSharedObject)
//MyBookQueue {
//public:
//    static MyBookQueue* create();
//
//    bool enqueue(CFTypeRef ref);
//    CF_RETURNS_NOT_RETAINED _Nullable CFTypeRef try_dequeue();
//private:
//    MyBookQueue();
//    CFDataRef data;
////    class MyActualType;
////    std::unique_ptr<MyActualType> impl;
//};

CF_EXTERN_C_BEGIN

bool enqueue_ref_concurrent_queue(void*  queue, CFTypeRef  ref);

CF_RETURNS_RETAINED CFRunLoopSourceRef create_tetra_runLoop_executor(
    CFTypeRef initialState,
    const TetraContextData *tetraContext
);

CF_RETURNS_RETAINED CFDictionaryRef copy_tetra_runLoop_registry(CFRunLoopSourceRef source);

bool tetra_enqueue_and_signal(CFRunLoopSourceRef source, CFTypeRef ref);

CF_RETURNS_NOT_RETAINED
CFTypeRef tetra_get_stateInfo(CFRunLoopSourceRef source);

CF_EXTERN_C_END

//void retainSharedObject(MyBookQueue* ref);
//void releaseSharedObject(MyBookQueue* _Nullable ref);

CF_ASSUME_NONNULL_END



#endif /* ConcurrentQueue_shim_h */
