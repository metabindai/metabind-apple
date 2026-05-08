//
// AuthenticationInterceptor.swift
//
// © 2025 Yap Studios LLC
//

import Foundation
import Apollo
import ApolloAPI

class AuthenticationInterceptor: ApolloInterceptor {
   private let apiKey: String
   private let organizationId: String
   private let projectId: String
   
   init(apiKey: String, organizationId: String, projectId: String) {
      self.apiKey = apiKey
      self.organizationId = organizationId
      self.projectId = projectId
   }
   
   func interceptAsync<Operation>(
      chain: RequestChain,
      request: HTTPRequest<Operation>,
      response: HTTPResponse<Operation>?,
      completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
   ) where Operation : GraphQLOperation {
      // Add authentication headers
      request.addHeader(name: "x-api-key", value: "\(organizationId):\(projectId):\(apiKey)")
      
      // Continue with the chain
      chain.proceedAsync(
         request: request,
         response: response,
         interceptor: self,
         completion: completion
      )
   }
   
   var id: String = UUID().uuidString
}

class AuthenticationInterceptorProvider: InterceptorProvider {
   
   private let client: URLSessionClient
   private let authInterceptor: AuthenticationInterceptor
   private let store: ApolloStore
   private let shouldInvalidateClientOnDeinit: Bool
   
   /// Designated initializer
   ///
   /// - Parameters:
   ///   - client: The `URLSessionClient` to use. Defaults to the default setup.
   ///   - shouldInvalidateClientOnDeinit: If the passed-in client should be invalidated when this interceptor provider is deinitialized. If you are recreating the `URLSessionClient` every time you create a new provider, you should do this to prevent memory leaks. Defaults to true, since by default we provide a `URLSessionClient` to new instances.
   ///   - store: The `ApolloStore` to use when reading from or writing to the cache. Make sure you pass the same store to the `ApolloClient` instance you're planning to use.
   public init(client: URLSessionClient = URLSessionClient(),
               authInterceptor: AuthenticationInterceptor,
               shouldInvalidateClientOnDeinit: Bool = true,
               store: ApolloStore) {
      self.client = client
      self.authInterceptor = authInterceptor
      self.shouldInvalidateClientOnDeinit = shouldInvalidateClientOnDeinit
      self.store = store
   }
   
   deinit {
      if self.shouldInvalidateClientOnDeinit {
         self.client.invalidate()
      }
   }
   
   open func interceptors<Operation: GraphQLOperation>(
      for operation: Operation
   ) -> [any ApolloInterceptor] {
      return [
         authInterceptor,
         MaxRetryInterceptor(),
         CacheReadInterceptor(store: self.store),
         NetworkFetchInterceptor(client: self.client),
         ResponseCodeInterceptor(),
         MultipartResponseParsingInterceptor(),
         jsonParsingInterceptor(for: operation),
         AutomaticPersistedQueryInterceptor(),
         CacheWriteInterceptor(store: self.store),
      ]
   }
   
   private func jsonParsingInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> any ApolloInterceptor {
      if Operation.hasDeferredFragments {
         return IncrementalJSONResponseParsingInterceptor()
         
      } else {
         return JSONResponseParsingInterceptor()
      }
   }
   
   open func additionalErrorInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> (any ApolloErrorInterceptor)? {
      return nil
   }
}
