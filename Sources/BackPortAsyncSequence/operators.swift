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
