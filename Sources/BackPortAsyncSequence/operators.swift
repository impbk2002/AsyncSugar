//
//  operators.swift
//  
//
//  Created by 박병관 on 6/13/24.
//


extension AsyncSequence where AsyncIterator: TypedAsyncIteratorProtocol {
    
    func mapError<Err:Error>(
        _ mapError: @escaping @Sendable (AsyncIterator.Err) async throws(Err) -> Void
    ) -> some TypedAsyncSequence<Element, Err> {
        AsyncMapErrorSequence(base: self, mapError: mapError)
    }
    

    @_disfavoredOverload
    func map2<Err:Error, T>(
        _ map: @escaping @Sendable (AsyncIterator.Element) async throws(Err) -> T
    ) -> some TypedAsyncSequence<T,Err> where AsyncIterator.Err == Never {
        return BackPort.AsyncMapSequence(self, transform: map)
    }

    func map2<T>(
        _ map: @escaping @Sendable (AsyncIterator.Element) async throws(AsyncIterator.Err) -> T
    ) -> some TypedAsyncSequence<T, AsyncIterator.Err>  {
        BackPort.AsyncMapSequence(self, transform: map)
    }
    

}






@inline(__always)
@inlinable
package
func iteratorNextResult<Base: TypedAsyncIteratorProtocol>(
    _ actor: isolated (any Actor)? = #isolation,
    _ iterator: inout Base
) async -> sending Result<Base.Element,Base.Failure>? {
    do {
        if let value = try await iterator.next(isolation: actor) {
            return .success(value)
        }
        return nil
//      #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS
    } catch {
        return .failure(error)
    }
}

