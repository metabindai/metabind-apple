# Metabind

Swift SDK for the Metabind API. Fetch and render dynamic content in your iOS/iPadOS/macOS apps.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/metabindai/metabind-apple.git", from: "1.2.9")
]
```

## Quick Start

### 1. Initialize the Client

Create a `MetabindClient` and inject it into the SwiftUI environment:

```swift
import SwiftUI
import Metabind

@main
struct MyApp: App {
    @State var client = MetabindClient(
        url: URL(string: "https://api.metabind.ai/graphql")!,
        ws: URL(string: "wss://api.metabind.ai/graphql")!,
        apiKey: "your-api-key",
        organizationId: "your-org-id",
        projectId: "your-project-id"
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(client)
        }
    }
}
```

### 2. Render Content with MetabindView

`MetabindView` reads `MetabindClient` from the environment automatically. It handles fetching, caching, and rendering:

```swift
import SwiftUI
import Metabind

struct ContentScreen: View {
    var body: some View {
        MetabindView(contentId: "cont_123")
    }
}
```

**Features:**
- Automatic loading, error, and success states
- SQLite-backed caching with cache-then-network updates
- Optional real-time subscriptions via WebSocket
- Task lifecycle tied to view (automatic cancellation)

**With Real-time Updates:**

```swift
// Enable WebSocket subscription for live updates
MetabindView(contentId: "cont_123", enableSubscription: true)
```

When `enableSubscription: true`, the view runs both the content stream (for initial load) and a WebSocket subscription (for real-time updates from the CMS).

## GraphQL APIs

For more control, use the `MetabindClient` APIs directly.

For complete API documentation, see the [Metabind GraphQL Documentation](https://docs.metabind.ai/graphql/overview). You can also view the [GraphQL schema](schema.graphqls) in this repository.

All APIs follow a consistent pattern:

- **`fetch*()`** - Single async/await request
- **`stream*()`** - AsyncStream that yields cached data first, then network updates
- **`subscribeTo*()`** - Real-time WebSocket subscription (content only)

### Content

Fetch and display individual content entries.

```swift
// Fetch single content
let content = try await client.fetchContent(id: "cont_123")

// Stream content (cache -> network)
for await result in client.streamContent(id: "cont_123") {
    switch result {
    case .success(let content):
        // Update UI
    case .failure(let error):
        // Handle error
    }
}

// Subscribe to real-time updates
for await result in client.subscribeToContent(id: "cont_123") {
    switch result {
    case .success(let content):
        // Handle live update
    case .failure(let error):
        // Handle error
    }
}
```

### Contents (List)

Fetch paginated lists of content with filtering and sorting.

```swift
// Fetch contents with filtering
let contentsList = try await client.fetchContents(
    typeId: "type_123",           // Filter by content type
    tags: ["featured", "new"],    // Filter by tags
    locale: "en-US",              // Filter by locale
    search: "hello",              // Text search
    filter: ContentFilter(...),   // Advanced filtering
    sort: [SortCriteria(...)],    // Sorting
    cursor: nil,                  // Pagination cursor
    limit: 20                     // Page size
)

let items = contentsList.data
let hasMore = contentsList.pagination.hasMore
let nextCursor = contentsList.pagination.cursor

// Stream contents list
for await result in client.streamContents(typeId: "type_123", tags: ["featured"]) {
    // Handle updates
}
```

### Components

Fetch component definitions.

```swift
// Fetch single component
let component = try await client.fetchComponent(id: "comp_123")

// Fetch component list with search
let components = try await client.fetchComponents(
    search: "Button",
    cursor: nil,
    limit: 20
)

// Stream components
for await result in client.streamComponents(search: "Card") {
    // Handle updates
}
```

### Content Types

Fetch content type schemas.

```swift
// Fetch single content type
let contentType = try await client.fetchContentType(id: "type_123")
let schema = try contentType.parsedSchema()  // Parse schema JSON

// Fetch content type list
let contentTypes = try await client.fetchContentTypes(
    search: "Article",
    cursor: nil,
    limit: 20
)

// Stream content types
for await result in client.streamContentTypes() {
    // Handle updates
}
```

### Assets

Fetch media assets (images, videos, files).

```swift
// Fetch single asset
let asset = try await client.fetchAsset(id: "asset_123")

// Fetch asset list with filtering
let assets = try await client.fetchAssets(
    type: "image/jpeg",           // Filter by MIME type
    tags: ["hero", "banner"],     // Filter by tags
    search: "logo",               // Text search
    filter: AssetFilter(...),     // Advanced filtering
    sort: [SortCriteria(...)],    // Sorting
    cursor: nil,
    limit: 20
)

// Stream assets
for await result in client.streamAssets(type: "image/png") {
    // Handle updates
}
```

### Tags

Fetch tags used for organizing content and assets.

```swift
// Fetch single tag
let tag = try await client.fetchTag(id: "tag_123")

// Fetch tag list
let tags = try await client.fetchTags(
    search: "category",
    cursor: nil,
    limit: 20
)

// Stream tags
for await result in client.streamTags() {
    // Handle updates
}
```

### Packages

Fetch published component packages (versioned snapshots).

```swift
// Fetch single package by version
let package = try await client.fetchPackage(version: "1.0.0")

// Fetch package list
let packages = try await client.fetchPackages(
    cursor: nil,
    limit: 20
)

// Stream packages
for await result in client.streamPackages() {
    // Handle updates
}
```

### Saved Searches

Execute pre-configured searches created in the CMS.

```swift
// Fetch saved search definition
let savedSearch = try await client.fetchSavedSearch(id: "search_123")

// Fetch saved search list
let savedSearches = try await client.fetchSavedSearches(
    type: .case(.CONTENT),  // or .ASSET
    cursor: nil,
    limit: 20
)

// Execute saved search and get results
let results = try await client.executeSavedSearch(
    id: "search_123",
    cursor: nil,
    limit: 20
)

// Results are a union type (ContentList or AssetList)
if let contentList = results.asContentList {
    let contents = contentList.data
} else if let assetList = results.asAssetList {
    let assets = assetList.data
}
```

## Direct Rendering with BindJSView

For advanced use cases, fetch content and render with `BindJSView` directly:

```swift
import SwiftUI
import Metabind
import BindJS

struct CustomContentView: View {
    @Environment(MetabindClient.self) var client
    @State private var resolvedContent: ResolvedContent?

    let contentId: String

    var body: some View {
        Group {
            if let content = resolvedContent {
                BindJSView(content: content)
            } else {
                ProgressView()
            }
        }
        .task {
            await loadContent()
        }
    }

    func loadContent() async {
        do {
            let content = try await client.fetchContent(id: contentId)
            resolvedContent = try await content.resolvedContent(using: client)
        } catch {
            print("Error: \(error)")
        }
    }
}
```

### Parsing Content Data

Extract structured data from content for application logic:

```swift
let content = try await client.fetchContent(id: "cont_123")

// Parse content JSON into PropertyValue map
let propertyMap = try content.parsedContent()

// Access nested data
let title = propertyMap["title"]?.string
let items = propertyMap["items"]?.array
let metadata = propertyMap["metadata"]?.object
```

## Cache Policies

Control caching behavior with `CachePolicy`:

| Policy | Description | Use Case |
|--------|-------------|----------|
| `.fetchIgnoringCacheData` | Always fetch from network | Default for `fetch*()` methods |
| `.returnCacheDataDontFetch` | Only return cached data | Offline mode, instant display |
| `.returnCacheDataAndFetch` | Yield cache, then network | **Only for `stream*()` methods** |
| `.returnCacheDataElseFetch` | Cache if available, else network | Avoid with `fetch*()` |

```swift
// Force network fetch
let content = try await client.fetchContent(
    id: "cont_123",
    cachePolicy: .fetchIgnoringCacheData
)

// Try cache only (for instant display)
let cached = try await client.fetchContent(
    id: "cont_123",
    cachePolicy: .returnCacheDataDontFetch
)
```

## Error Handling

```swift
do {
    let content = try await client.fetchContent(id: "cont_123")
} catch MetabindClientError.noData {
    // Content not found
} catch MetabindClientError.graphQLErrors(let messages) {
    // GraphQL errors (e.g., validation, permissions)
    print("Errors: \(messages)")
} catch MetabindClientError.missingResolvedPackage {
    // Package resolution failed
} catch MetabindClientError.invalidComponentsJSON {
    // Package component parsing failed
} catch {
    // Network or other errors
}
```

## Features

- **SQLite Cache**: Persistent cache in app documents directory
- **Authentication**: Automatic API key injection for HTTP and WebSocket
- **WebSocket Support**: Real-time subscriptions with auto-reconnect
- **Async/Await**: Modern Swift concurrency throughout
- **Type Safety**: Fully generated types from GraphQL schema
- **SwiftUI Integration**: Purpose-built views for Metabind content

## Dependencies

- Apollo iOS 1.23.0 (GraphQL client with WebSocket and SQLite support)
- BindJS (component rendering engine)

## Regenerating GraphQL Code

When the GraphQL schema or queries change:

```bash
./apollo-ios-cli generate
```

Generated code is placed in `Sources/Metabind/generated/`. Never edit these files manually.
