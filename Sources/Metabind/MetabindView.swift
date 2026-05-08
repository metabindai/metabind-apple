//
// MetabindView.swift
//
// © 2025 Yap Studios LLC
//

import SwiftUI
import BindJS
import Apollo

/// Async wrapper that fetches content via GraphQL then renders
public struct MetabindView: View {
    @State private var viewModel: MetabindViewModel
    @Environment(MetabindClient.self) var client

    let enableSubscription: Bool

    public init(contentId: String, enableSubscription: Bool = false) {
        _viewModel = State(wrappedValue: MetabindViewModel(contentId: contentId, enableSubscription: enableSubscription))
        self.enableSubscription = enableSubscription
    }

    public var body: some View {
        Group {
            if let resolvedContent = viewModel.resolvedContent {
                // Pass data to pure rendering view
                BindJSView(content: resolvedContent)
                    .withComponent(MetabindViewComponent.self)

            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let error = viewModel.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Failed to load content")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .task(id: viewModel.contentId) {
            await viewModel.streamContent(using: client)
        }
        .task(id: viewModel.contentId) {
            if enableSubscription {
                await viewModel.subscribeToContent(using: client)
            }
        }
    }
}

/// View model for async content loading
@Observable
@MainActor
class MetabindViewModel {
    let contentId: String
    let enableSubscription: Bool

    var resolvedContent: ResolvedContent?
    var error: Error?
    var isLoading = true

    /// Tracks the last updatedAt timestamp to detect content changes
    private var lastUpdatedAt: String?

    init(contentId: String, enableSubscription: Bool = false) {
        self.contentId = contentId
        self.enableSubscription = enableSubscription
    }

    func streamContent(using client: MetabindClient) async {
        isLoading = true
        error = nil

        for await result in client.streamContent(id: contentId) {
            switch result {
            case .success(let contentData):
                do {
                    // If we already have compiled content and all packages are published (immutable),
                    // we can skip reloading — unless the content itself has changed (detected via updatedAt)
                    let updatedAt = contentData.fragments.contentFields.updatedAt
                    if resolvedContent != nil && !contentData.hasDraftPackages {
                        if updatedAt == lastUpdatedAt {
                            continue
                        }
                    }
                    lastUpdatedAt = updatedAt

                    // First load: try cache first for instant display
                    if resolvedContent == nil {
                        if let cached = try? await contentData.resolvedContent(
                            using: client,
                            cachePolicy: .returnCacheDataDontFetch
                        ) {
                            // Successfully loaded from cache - display immediately
                            self.resolvedContent = cached
                            self.isLoading = false

                            // If there are no draft packages, we're done (published packages are immutable)
                            if !contentData.hasDraftPackages {
                                continue
                            }
                            // Fall through to fetch fresh draft packages
                        }
                    }

                    // Normal flow: fetch from network (first load cache miss, draft updates, or content changes)
                    self.resolvedContent = try await contentData.resolvedContent(using: client)
                    self.isLoading = false
                    self.error = nil
                } catch {
                    // Handle compilation errors but keep stream alive
                    self.error = error
                    self.isLoading = false
                }

            case .failure(let streamError):
                // Handle stream errors but keep stream alive
                self.error = streamError
                self.isLoading = false
            }
        }
    }

    func subscribeToContent(using client: MetabindClient) async {
        for await result in client.subscribeToContent(id: contentId) {
            switch result {
            case .success:
                // No need to process content here - the subscription writes to Apollo cache
                // and streamContent's watcher will automatically pick up the cache update
                // This keeps the data flow unidirectional and avoids duplicate package fetches
                break

            case .failure(let error):
                // Log subscription errors but don't show error UI
                // (streamContent will handle initial load errors)
                print("Subscription error for content \(contentId): \(error)")
            }
        }
    }
}
