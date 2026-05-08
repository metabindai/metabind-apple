//
// MetabindClient.swift
//
// © 2025 Yap Studios LLC
//

import SwiftUI
import Apollo
@_exported import enum Apollo.CachePolicy
@_exported import ApolloAPI
import ApolloWebSocket
import ApolloSQLite
import BindJS
import Foundation
import CryptoKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


@Observable
public class MetabindClient {
    public let apolloClient: ApolloClient
    private let webSocketTransport: WebSocketTransport

    public init(url: URL, ws: URL, apiKey: String, organizationId: String, projectId: String) {

        // Create SQLite cache with URL-specific hash to support multiple client instances
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let urlHash = Self.hashURL(url)
        let sqlitePath = documentsPath.appendingPathComponent("MetabindClientCache-\(urlHash).sqlite")
        
        let sqliteCache = try! SQLiteNormalizedCache(fileURL: sqlitePath)
        let store = ApolloStore(cache: sqliteCache)
        
        // Create authentication interceptor
        let authInterceptor = AuthenticationInterceptor(
            apiKey: apiKey,
            organizationId: organizationId,
            projectId: projectId
        )
        
        // Create URL session client
        let client = URLSessionClient()
        
        // Create interceptor provider
        let interceptorProvider = AuthenticationInterceptorProvider(
            client: client,
            authInterceptor: authInterceptor,
            store: store
        )
        
        // Create HTTP transport
        let httpTransport = RequestChainNetworkTransport(
            interceptorProvider: interceptorProvider,
            endpointURL: url
        )
        
        // Create WebSocket transport
        self.webSocketTransport = WebSocketTransport(
            websocket: WebSocket(
                url: ws,
                protocol: .graphql_transport_ws
            ),
            store: store
        )

        // Add authentication to WebSocket
        let payload: JSONEncodableDictionary = [
            "apiKey": apiKey,
            "organizationId": organizationId,
            "projectId": projectId
        ]
        webSocketTransport.updateConnectingPayload(payload)

        // Create split network transport
        let splitTransport = SplitNetworkTransport(
            uploadingNetworkTransport: httpTransport,
            webSocketNetworkTransport: webSocketTransport
        )

        // Initialize Apollo client
        self.apolloClient = ApolloClient(
            networkTransport: splitTransport,
            store: store
        )

        // Setup lifecycle observers for WebSocket pause/resume
        setupLifecycleObservers()
    }

    deinit {
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self)
        #elseif canImport(AppKit)
        NotificationCenter.default.removeObserver(self)
        #endif
    }

    // MARK: - Helper Methods

    /// Creates a deterministic hash from a URL for cache filename uniqueness.
    /// The hash persists across app sessions for the same URL.
    /// - Parameter url: The URL to hash
    /// - Returns: A hex string representation of the SHA256 hash
    private static func hashURL(_ url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Lifecycle Management

    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #elseif canImport(AppKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        #endif
    }

    #if canImport(UIKit)
    @objc private func handleDidEnterBackground() {
        webSocketTransport.pauseWebSocketConnection()
    }

    @objc private func handleWillEnterForeground() {
        webSocketTransport.resumeWebSocketConnection(autoReconnect: true)
    }
    #elseif canImport(AppKit)
    @objc private func handleDidResignActive() {
        webSocketTransport.pauseWebSocketConnection()
    }

    @objc private func handleDidBecomeActive() {
        webSocketTransport.resumeWebSocketConnection(autoReconnect: true)
    }
    #endif

    // MARK: - Package Resolution Helpers

    /// Fetches all resolved packages (main package + dependencies) in parallel.
    /// This is a core helper method used by content and component compilation.
    /// - Parameters:
    ///   - resolvedRef: The resolved package reference containing package and dependency IDs
    ///   - cachePolicy: Optional cache policy override. If nil, uses smart defaults (cache-else-fetch for published, network-only for drafts)
    /// - Returns: PackageComponents with version and component map ready for rendering
    /// - Throws: An error if package data fetching or parsing fails
    public func fetchResolvedPackages(
        resolvedRef: ResolvedPackageRefFields,
        cachePolicy: Apollo.CachePolicy? = nil
    ) async throws -> PackageComponents {
        // Fetch package and all dependencies in parallel using task group
        let packageIds = [resolvedRef.package] + resolvedRef.dependencies

        let packageDataList = try await withThrowingTaskGroup(of: (Int, ResolvedPackageDataFields).self) { group in
            for (index, packageId) in packageIds.enumerated() {
                group.addTask {
                    let packageData = try await self.fetchResolvedPackageData(id: packageId, cachePolicy: cachePolicy)
                    return (index, packageData.fragments.resolvedPackageDataFields)
                }
            }

            var indexedResults: [(Int, ResolvedPackageDataFields)] = []
            for try await result in group {
                indexedResults.append(result)
            }

            // Sort by index to preserve order (main package first, then dependencies)
            return indexedResults
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }

        guard let mainPackage = packageDataList.first else {
            throw MetabindClientError.missingResolvedPackage
        }

        // Parse components JSON from main package
        guard let componentsData = mainPackage.components.data(using: .utf8),
              let components = try? JSONDecoder().decode([String: String].self, from: componentsData)
        else {
            throw MetabindClientError.invalidComponentsJSON
        }

        return PackageComponents(
            version: mainPackage.version,
            components: components
        )
    }

    // MARK: - Resolved Package Data Query

    /// Fetches resolved package data with the specified id.
    /// - Parameters:
    ///   - id: The ID of the resolved package (either SHA-256 hash or draft:{projectId}:{organizationId}).
    ///   - cachePolicy: The cache policy to use. Defaults to .returnCacheDataElseFetch for published packages, but should use .fetchIgnoringCacheData for draft packages.
    /// - Returns: Resolved package data.
    /// - Throws: An error if the request fails or data is missing.
    public func fetchResolvedPackageData(id: String, cachePolicy: Apollo.CachePolicy? = nil) async throws -> ResolvedPackageDataQuery.Data.ResolvedPackageData {
        // Determine cache policy based on draft status if not explicitly provided
        let isDraft = id.hasPrefix("draft:")
        let effectiveCachePolicy = cachePolicy ?? (isDraft ? .fetchIgnoringCacheData : .returnCacheDataElseFetch)

        return try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ResolvedPackageDataQuery(packageId: id),
                cachePolicy: effectiveCachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    // Check for GraphQL errors
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let packageData = graphQLResult.data?.resolvedPackageData else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: packageData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Content Query

    /// Fetches content with the specified id.
    /// - Parameters:
    ///   - id: The ID of the content.
    ///   - cachePolicy: The cache policy to use (default: .fetchIgnoringCacheData).
    /// - Returns: Content data.
    /// - Throws: An error if the request fails or data is missing.
    public func fetchContent(id: String, cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData) async throws -> ContentQuery.Data.Content {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ContentQuery(id: id),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    // Check for GraphQL errors
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let content = graphQLResult.data?.content else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: content)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams content with the specified id, watching for updates.
    /// Returns Result type to prevent stream cancellation on transient errors.
    /// - Parameter id: The ID of the content.
    /// - Returns: An AsyncStream that yields Result with content updates or errors.
    public func streamContent(id: String) -> AsyncStream<Result<ContentQuery.Data.Content, Error>> {
        AsyncStream { continuation in
            let watcher = apolloClient.watch(
                query: ContentQuery(id: id),
                cachePolicy: .returnCacheDataAndFetch,
                callbackQueue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    // Check for GraphQL errors
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let content = graphQLResult.data?.content else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    continuation.yield(.success(content))
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                watcher.cancel()
            }
        }
    }

    /// Subscribes to real-time updates for content with the specified id.
    /// If content is null (payload too large), fetches content with cache policy and writes to Apollo cache.
    /// Returns Result type to prevent subscription cancellation on transient errors.
    /// - Parameter id: The ID of the content.
    /// - Returns: An AsyncStream that yields Result with content updates or errors.
    public func subscribeToContent(id: String) -> AsyncStream<Result<ContentQuery.Data.Content, Error>> {
        AsyncStream { continuation in
            let subscription = apolloClient.subscribe(
                subscription: ContentUpdatedSubscription(id: id)
            ) { [weak self] result in
                guard let self = self else { return }

                do {
                    let graphQLResult = try result.get()

                    // Check for GraphQL errors
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let contentUpdate = graphQLResult.data?.contentUpdated else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    // If content is null (payload too large), fetch it with fetchIgnoringCacheData
                    if let content = contentUpdate.content {
                        // Content is present, yield it directly
                        // Convert subscription content type to query content type
                        // Both use ContentFields fragment so we can reconstruct
                        let queryContent = ContentQuery.Data.Content(_dataDict: content.__data)
                        continuation.yield(.success(queryContent))
                    } else {
                        // Content is null, fetch it using existing fetchContent method
                        Task {
                            do {
                                let fetchedContent = try await self.fetchContent(
                                    id: contentUpdate.contentId,
                                    cachePolicy: .fetchIgnoringCacheData
                                )
                                continuation.yield(.success(fetchedContent))
                            } catch {
                                continuation.yield(.failure(error))
                            }
                        }
                    }
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }

    // MARK: - Contents Query

    /// Fetches contents with optional filtering and cursor-based pagination.
    /// - Parameters:
    ///   - typeId: Optional type ID to filter by.
    ///   - tags: Optional tags to filter by.
    ///   - locale: Optional locale to filter by.
    ///   - search: Optional search string.
    ///   - filter: Optional content filter.
    ///   - sort: Optional sort criteria.
    ///   - cursor: Optional cursor for pagination.
    ///   - limit: Items per page (default: 20).
    ///   - cachePolicy: The cache policy to use (default: .fetchIgnoringCacheData).
    /// - Returns: Contents list with data and pagination.
    /// - Throws: An error if the request fails or data is missing.
    public func fetchContents(
        typeId: String? = nil,
        tags: [String]? = nil,
        locale: String? = nil,
        search: String? = nil,
        filter: ContentFilter? = nil,
        sort: [SortCriteria]? = nil,
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> ContentsQuery.Data.Contents {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ContentsQuery(
                    typeId: typeId.map { .some($0) } ?? .none,
                    tags: tags.map { .some($0) } ?? .none,
                    locale: locale.map { .some($0) } ?? .none,
                    search: search.map { .some($0) } ?? .none,
                    filter: filter.map { .some($0) } ?? .none,
                    sort: sort.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    // Check for GraphQL errors
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let contents = graphQLResult.data?.contents else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: contents)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams contents with optional filtering and cursor-based pagination, watching for updates.
    /// Returns Result type to prevent stream cancellation on transient errors.
    /// - Parameters:
    ///   - typeId: Optional type ID to filter by.
    ///   - tags: Optional tags to filter by.
    ///   - locale: Optional locale to filter by.
    ///   - search: Optional search string.
    ///   - filter: Optional content filter.
    ///   - sort: Optional sort criteria.
    ///   - cursor: Optional cursor for pagination.
    ///   - limit: Items per page (default: 20).
    /// - Returns: An AsyncStream that yields Result with contents updates or errors.
    public func streamContents(
        typeId: String? = nil,
        tags: [String]? = nil,
        locale: String? = nil,
        search: String? = nil,
        filter: ContentFilter? = nil,
        sort: [SortCriteria]? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) -> AsyncStream<Result<ContentsQuery.Data.Contents, Error>> {
        AsyncStream { continuation in
            let watcher = apolloClient.watch(
                query: ContentsQuery(
                    typeId: typeId.map { .some($0) } ?? .none,
                    tags: tags.map { .some($0) } ?? .none,
                    locale: locale.map { .some($0) } ?? .none,
                    search: search.map { .some($0) } ?? .none,
                    filter: filter.map { .some($0) } ?? .none,
                    sort: sort.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: .returnCacheDataAndFetch,
                callbackQueue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    // Check for GraphQL errors
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let contents = graphQLResult.data?.contents else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    continuation.yield(.success(contents))
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                watcher.cancel()
            }
        }
    }

    // MARK: - Component Query

    /// Fetches a single component by ID.
    /// - Parameters:
    ///   - id: The unique identifier of the component.
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: The component data including compiled code, schema, and metadata.
    /// - Throws: `MetabindClientError.noData` if not found, or GraphQL errors.
    public func fetchComponent(id: String, cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData) async throws -> ComponentQuery.Data.Component {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ComponentQuery(id: id),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let component = graphQLResult.data?.component else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: component)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetches a paginated list of components with optional search filtering.
    /// - Parameters:
    ///   - search: Optional search string to filter components by name.
    ///   - cursor: Optional cursor for pagination (from previous response).
    ///   - limit: Maximum number of components to return (default: 20).
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: Component list with data and pagination info.
    /// - Throws: `MetabindClientError.noData` if request fails, or GraphQL errors.
    public func fetchComponents(
        search: String? = nil,
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> ComponentsQuery.Data.Components {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ComponentsQuery(
                    search: search.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let components = graphQLResult.data?.components else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: components)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams a paginated list of components, watching for updates.
    /// Returns Result type to prevent stream cancellation on transient errors.
    /// - Parameters:
    ///   - search: Optional search string to filter components by name.
    ///   - cursor: Optional cursor for pagination.
    ///   - limit: Maximum number of components to return (default: 20).
    /// - Returns: An AsyncStream that yields Result with component list updates or errors.
    public func streamComponents(
        search: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) -> AsyncStream<Result<ComponentsQuery.Data.Components, Error>> {
        AsyncStream { continuation in
            let watcher = apolloClient.watch(
                query: ComponentsQuery(
                    search: search.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: .returnCacheDataAndFetch,
                callbackQueue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let components = graphQLResult.data?.components else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    continuation.yield(.success(components))
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                watcher.cancel()
            }
        }
    }

    // MARK: - ContentType Query

    /// Fetches a single content type by ID.
    /// - Parameters:
    ///   - id: The unique identifier of the content type.
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: The content type data including schema definition.
    /// - Throws: `MetabindClientError.noData` if not found, or GraphQL errors.
    public func fetchContentType(id: String, cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData) async throws -> ContentTypeQuery.Data.ContentType {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ContentTypeQuery(id: id),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let contentType = graphQLResult.data?.contentType else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: contentType)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetches a paginated list of content types with optional search filtering.
    /// - Parameters:
    ///   - search: Optional search string to filter content types by name.
    ///   - cursor: Optional cursor for pagination (from previous response).
    ///   - limit: Maximum number of content types to return (default: 20).
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: Content type list with data and pagination info.
    /// - Throws: `MetabindClientError.noData` if request fails, or GraphQL errors.
    public func fetchContentTypes(
        search: String? = nil,
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> ContentTypesQuery.Data.ContentTypes {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ContentTypesQuery(
                    search: search.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let contentTypes = graphQLResult.data?.contentTypes else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: contentTypes)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams a paginated list of content types, watching for updates.
    /// Returns Result type to prevent stream cancellation on transient errors.
    /// - Parameters:
    ///   - search: Optional search string to filter content types by name.
    ///   - cursor: Optional cursor for pagination.
    ///   - limit: Maximum number of content types to return (default: 20).
    /// - Returns: An AsyncStream that yields Result with content type list updates or errors.
    public func streamContentTypes(
        search: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) -> AsyncStream<Result<ContentTypesQuery.Data.ContentTypes, Error>> {
        AsyncStream { continuation in
            let watcher = apolloClient.watch(
                query: ContentTypesQuery(
                    search: search.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: .returnCacheDataAndFetch,
                callbackQueue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let contentTypes = graphQLResult.data?.contentTypes else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    continuation.yield(.success(contentTypes))
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                watcher.cancel()
            }
        }
    }

    // MARK: - Asset Query

    /// Fetches a single asset by ID.
    /// - Parameters:
    ///   - id: The unique identifier of the asset.
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: The asset data including URL, dimensions, and metadata.
    /// - Throws: `MetabindClientError.noData` if not found, or GraphQL errors.
    public func fetchAsset(id: String, cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData) async throws -> AssetQuery.Data.Asset {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: AssetQuery(id: id),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let asset = graphQLResult.data?.asset else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: asset)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetches a paginated list of assets with optional filtering and sorting.
    /// - Parameters:
    ///   - type: Optional MIME type to filter by (e.g., "image/jpeg").
    ///   - tags: Optional tags to filter by.
    ///   - search: Optional search string to filter assets by name.
    ///   - filter: Optional asset filter for advanced filtering.
    ///   - sort: Optional sort criteria.
    ///   - cursor: Optional cursor for pagination (from previous response).
    ///   - limit: Maximum number of assets to return (default: 20).
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: Asset list with data and pagination info.
    /// - Throws: `MetabindClientError.noData` if request fails, or GraphQL errors.
    public func fetchAssets(
        type: String? = nil,
        tags: [String]? = nil,
        search: String? = nil,
        filter: AssetFilter? = nil,
        sort: [SortCriteria]? = nil,
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> AssetsQuery.Data.Assets {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: AssetsQuery(
                    type: type.map { .some($0) } ?? .none,
                    tags: tags.map { .some($0) } ?? .none,
                    search: search.map { .some($0) } ?? .none,
                    filter: filter.map { .some($0) } ?? .none,
                    sort: sort.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let assets = graphQLResult.data?.assets else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: assets)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams a paginated list of assets, watching for updates.
    /// Returns Result type to prevent stream cancellation on transient errors.
    /// - Parameters:
    ///   - type: Optional MIME type to filter by.
    ///   - tags: Optional tags to filter by.
    ///   - search: Optional search string to filter assets by name.
    ///   - filter: Optional asset filter for advanced filtering.
    ///   - sort: Optional sort criteria.
    ///   - cursor: Optional cursor for pagination.
    ///   - limit: Maximum number of assets to return (default: 20).
    /// - Returns: An AsyncStream that yields Result with asset list updates or errors.
    public func streamAssets(
        type: String? = nil,
        tags: [String]? = nil,
        search: String? = nil,
        filter: AssetFilter? = nil,
        sort: [SortCriteria]? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) -> AsyncStream<Result<AssetsQuery.Data.Assets, Error>> {
        AsyncStream { continuation in
            let watcher = apolloClient.watch(
                query: AssetsQuery(
                    type: type.map { .some($0) } ?? .none,
                    tags: tags.map { .some($0) } ?? .none,
                    search: search.map { .some($0) } ?? .none,
                    filter: filter.map { .some($0) } ?? .none,
                    sort: sort.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: .returnCacheDataAndFetch,
                callbackQueue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let assets = graphQLResult.data?.assets else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    continuation.yield(.success(assets))
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                watcher.cancel()
            }
        }
    }

    // MARK: - Tag Query

    /// Fetches a single tag by ID.
    /// - Parameters:
    ///   - id: The unique identifier of the tag.
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: The tag data including name, slug, and description.
    /// - Throws: `MetabindClientError.noData` if not found, or GraphQL errors.
    public func fetchTag(id: String, cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData) async throws -> TagQuery.Data.Tag {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: TagQuery(id: id),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let tag = graphQLResult.data?.tag else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: tag)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetches a paginated list of tags with optional search filtering.
    /// - Parameters:
    ///   - search: Optional search string to filter tags by name.
    ///   - cursor: Optional cursor for pagination (from previous response).
    ///   - limit: Maximum number of tags to return (default: 20).
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: Tag list with data and pagination info.
    /// - Throws: `MetabindClientError.noData` if request fails, or GraphQL errors.
    public func fetchTags(
        search: String? = nil,
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> TagsQuery.Data.Tags {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: TagsQuery(
                    search: search.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let tags = graphQLResult.data?.tags else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: tags)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams a paginated list of tags, watching for updates.
    /// Returns Result type to prevent stream cancellation on transient errors.
    /// - Parameters:
    ///   - search: Optional search string to filter tags by name.
    ///   - cursor: Optional cursor for pagination.
    ///   - limit: Maximum number of tags to return (default: 20).
    /// - Returns: An AsyncStream that yields Result with tag list updates or errors.
    public func streamTags(
        search: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) -> AsyncStream<Result<TagsQuery.Data.Tags, Error>> {
        AsyncStream { continuation in
            let watcher = apolloClient.watch(
                query: TagsQuery(
                    search: search.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: .returnCacheDataAndFetch,
                callbackQueue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let tags = graphQLResult.data?.tags else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    continuation.yield(.success(tags))
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                watcher.cancel()
            }
        }
    }

    // MARK: - Package Query

    /// Fetches a single package by version string.
    /// - Parameters:
    ///   - version: The version string of the package (e.g., "1.0.0").
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: The package data including components, assets, and dependencies.
    /// - Throws: `MetabindClientError.noData` if not found, or GraphQL errors.
    public func fetchPackage(version: String, cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData) async throws -> PackageQuery.Data.Package {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: PackageQuery(version: version),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let package = graphQLResult.data?.package else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: package)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetches a paginated list of packages.
    /// - Parameters:
    ///   - cursor: Optional cursor for pagination (from previous response).
    ///   - limit: Maximum number of packages to return (default: 20).
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: Package list with data and pagination info.
    /// - Throws: `MetabindClientError.noData` if request fails, or GraphQL errors.
    public func fetchPackages(
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> PackagesQuery.Data.Packages {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: PackagesQuery(
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let packages = graphQLResult.data?.packages else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: packages)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams a paginated list of packages, watching for updates.
    /// Returns Result type to prevent stream cancellation on transient errors.
    /// - Parameters:
    ///   - cursor: Optional cursor for pagination.
    ///   - limit: Maximum number of packages to return (default: 20).
    /// - Returns: An AsyncStream that yields Result with package list updates or errors.
    public func streamPackages(
        cursor: String? = nil,
        limit: Int = 20
    ) -> AsyncStream<Result<PackagesQuery.Data.Packages, Error>> {
        AsyncStream { continuation in
            let watcher = apolloClient.watch(
                query: PackagesQuery(
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: .returnCacheDataAndFetch,
                callbackQueue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.yield(.failure(MetabindClientError.graphQLErrors(errors.compactMap { $0.message })))
                        return
                    }

                    guard let packages = graphQLResult.data?.packages else {
                        continuation.yield(.failure(MetabindClientError.noData))
                        return
                    }

                    continuation.yield(.success(packages))
                } catch {
                    continuation.yield(.failure(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                watcher.cancel()
            }
        }
    }

    // MARK: - SavedSearch Query

    /// Fetches a single saved search by ID.
    /// - Parameters:
    ///   - id: The unique identifier of the saved search.
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: The saved search data including name, description, and type.
    /// - Throws: `MetabindClientError.noData` if not found, or GraphQL errors.
    public func fetchSavedSearch(id: String, cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData) async throws -> SavedSearchQuery.Data.SavedSearch {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: SavedSearchQuery(id: id),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let savedSearch = graphQLResult.data?.savedSearch else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: savedSearch)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetches a paginated list of saved searches with optional type filtering.
    /// - Parameters:
    ///   - type: Optional type to filter by (CONTENT or ASSET).
    ///   - cursor: Optional cursor for pagination (from previous response).
    ///   - limit: Maximum number of saved searches to return (default: 20).
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: Saved search list with data and pagination info.
    /// - Throws: `MetabindClientError.noData` if request fails, or GraphQL errors.
    public func fetchSavedSearches(
        type: GraphQLEnum<SavedSearchType>? = nil,
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> SavedSearchesQuery.Data.SavedSearches {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: SavedSearchesQuery(
                    type: type.map { .some($0) } ?? .none,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let savedSearches = graphQLResult.data?.savedSearches else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: savedSearches)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Executes a saved search and returns paginated results.
    /// Returns either a ContentList or AssetList depending on the saved search type.
    /// - Parameters:
    ///   - id: The unique identifier of the saved search to execute.
    ///   - cursor: Optional cursor for pagination (from previous response).
    ///   - limit: Maximum number of results to return (default: 20).
    ///   - cachePolicy: The cache policy to use (default: `.fetchIgnoringCacheData`).
    /// - Returns: Search results as either ContentList or AssetList union type.
    /// - Throws: `MetabindClientError.noData` if request fails, or GraphQL errors.
    public func executeSavedSearch(
        id: String,
        cursor: String? = nil,
        limit: Int = 20,
        cachePolicy: Apollo.CachePolicy = .fetchIgnoringCacheData
    ) async throws -> ExecuteSavedSearchQuery.Data.ExecuteSavedSearch {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: ExecuteSavedSearchQuery(
                    id: id,
                    cursor: cursor.map { .some($0) } ?? .none,
                    limit: .some(limit)
                ),
                cachePolicy: cachePolicy,
                queue: .global(qos: .userInitiated)
            ) { result in
                do {
                    let graphQLResult = try result.get()

                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: MetabindClientError.graphQLErrors(errors.compactMap { $0.message }))
                        return
                    }

                    guard let executeSavedSearch = graphQLResult.data?.executeSavedSearch else {
                        continuation.resume(throwing: MetabindClientError.noData)
                        return
                    }

                    continuation.resume(returning: executeSavedSearch)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Content Transformation Extensions

/// Extensions to transform GraphQL content into compiled content ready for rendering.
/// These extensions bridge the gap between raw GraphQL data and the CompiledContent
/// structure needed by MetabindView for JavaScript rendering.

// MARK: ResolvedPackageRefFields Fragment Extension

/// Extensions on ResolvedPackageRefFields fragment - shared by all content and component types
public extension ResolvedPackageRefFields {
    /// Check if any of the packages (main or dependencies) are in draft mode.
    /// Draft packages use the format `draft:{projectId}:{organizationId}` and are mutable.
    /// - Returns: `true` if any packages are drafts, `false` if all are published (immutable)
    var hasDraftPackages: Bool {
        let allPackageIds = [package] + dependencies
        return allPackageIds.contains { $0.hasPrefix("draft:") }
    }
}

// MARK: ContentFields Fragment Extension

/// Extensions on ContentFields fragment - shared by ContentQuery, ContentsQuery, and ContentUpdatedSubscription
public extension ContentFields {
    /// Check if any of the content's packages (main or dependencies) are in draft mode.
    /// Draft packages use the format `draft:{projectId}:{organizationId}` and are mutable.
    /// - Returns: `true` if any packages are drafts, `false` if all are published (immutable)
    var hasDraftPackages: Bool {
        resolvedRef.fragments.resolvedPackageRefFields.hasDraftPackages
    }

    /// Parse content JSON into PropertyValue map for application logic.
    /// Use this when you need to extract structured data from content (e.g., metadata, references).
    /// - Returns: PropertyValueMap containing parsed content structure
    /// - Throws: PropertyValueError if JSON is invalid
    func parsedContent() throws -> PropertyValueMap {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw PropertyValueError.invalidJSON
        }
        return try PropertyValueMap.from(json)
    }

    /// Get resolved content ready for rendering by fetching resolved package data.
    /// This is the primary method for preparing content for MetabindView rendering.
    ///
    /// Process:
    /// 1. Extracts package and dependency IDs from resolvedRef
    /// 2. Fetches all package data in parallel (with smart caching for published vs draft)
    /// 3. Parses component sources and combines into ResolvedContent
    ///
    /// - Parameters:
    ///   - client: The MetabindClient instance to use for fetching package data
    ///   - cachePolicy: Optional cache policy override. If nil, uses smart defaults (cache-else-fetch for published, network-only for drafts)
    /// - Returns: ResolvedContent with the main package and all dependencies loaded
    /// - Throws: An error if package data fetching or parsing fails
    ///
    /// Example:
    /// ```swift
    /// let content = try await client.fetchContent(id: "cont_123")
    /// let resolved = try await content.resolvedContent(using: client)
    /// MetabindView(content: resolved)
    /// ```
    func resolvedContent(using client: MetabindClient, cachePolicy: Apollo.CachePolicy? = nil) async throws -> ResolvedContent {
        let packageComponents = try await client.fetchResolvedPackages(
            resolvedRef: resolvedRef.fragments.resolvedPackageRefFields,
            cachePolicy: cachePolicy
        )

        return ResolvedContent(
            compiled: compiled,
            package: packageComponents
        )
    }
}

// MARK: ComponentFields Fragment Extension

/// Extensions on ComponentFields fragment
public extension ComponentFields {
    /// Get resolved component ready for rendering by fetching resolved package data.
    /// - Parameters:
    ///   - client: The MetabindClient instance to use for fetching package data
    ///   - resolvedRef: The resolved package reference with package and dependency IDs
    ///   - cachePolicy: Optional cache policy override. If nil, uses smart defaults
    /// - Returns: ResolvedContent with the component and all dependencies loaded
    /// - Throws: An error if package data fetching or parsing fails
    func resolvedContent(
        using client: MetabindClient,
        resolvedRef: ResolvedPackageRefFields,
        cachePolicy: Apollo.CachePolicy? = nil
    ) async throws -> ResolvedContent {
        let packageComponents = try await client.fetchResolvedPackages(
            resolvedRef: resolvedRef,
            cachePolicy: cachePolicy
        )

        return ResolvedContent(
            compiled: compiled,
            package: packageComponents
        )
    }
}

// MARK: ContentTypeFields Fragment Extension

/// Extensions on ContentTypeFields fragment
public extension ContentTypeFields {
    /// Parse the content type's schema JSON into a dictionary.
    /// - Returns: Dictionary representation of the content type's schema.
    /// - Throws: `MetabindClientError.invalidJSON` if schema parsing fails.
    func parsedSchema() throws -> [String: Any] {
        guard let data = schema.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw MetabindClientError.invalidJSON
        }
        return json
    }
}

// MARK: AssetFields Fragment Extension

/// Extensions on AssetFields fragment
public extension AssetFields {
    /// Returns true if this is an image asset (has width and height dimensions).
    var isImage: Bool {
        width != nil && height != nil
    }
}

// MARK: PackageFields Fragment Extension

/// Extensions on PackageFields fragment
public extension PackageFields {
    /// Check if any of the packages (main or dependencies) are in draft mode.
    /// Draft packages use the format `draft:{projectId}:{organizationId}` and are mutable.
    /// - Returns: `true` if any packages are drafts, `false` if all are published (immutable)
    var hasDraftPackages: Bool {
        resolvedRef.fragments.resolvedPackageRefFields.hasDraftPackages
    }
}

// MARK: Type-specific Extensions

/// ContentQuery.Data.Content extension - delegates to ContentFields fragment
public extension ContentQuery.Data.Content {
    /// Check if any of the content's packages are in draft mode
    var hasDraftPackages: Bool {
        fragments.contentFields.hasDraftPackages
    }

    /// Parse content JSON into PropertyValue map for application logic
    func parsedContent() throws -> PropertyValueMap {
        try fragments.contentFields.parsedContent()
    }

    /// Get resolved content ready for rendering by fetching resolved package data
    func resolvedContent(using client: MetabindClient, cachePolicy: Apollo.CachePolicy? = nil) async throws -> ResolvedContent {
        try await fragments.contentFields.resolvedContent(using: client, cachePolicy: cachePolicy)
    }
}

// MARK: - Errors

public enum MetabindClientError: Error, LocalizedError {
    case noData
    case graphQLErrors([String])
    case missingResolvedPackage
    case invalidComponentsJSON
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .noData:
            return "No content data returned from server"
        case .graphQLErrors(let messages):
            return "GraphQL errors: \(messages.joined(separator: ", "))"
        case .missingResolvedPackage:
            return "Content is missing resolved package data"
        case .invalidComponentsJSON:
            return "Failed to parse components JSON"
        case .invalidJSON:
            return "Failed to parse content JSON"
        }
    }
}
