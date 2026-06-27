# Metabind for Apple

The native Metabind SDK for iOS, iPadOS, macOS, and visionOS. Use it to build
server-driven UI from a content management system you control, and to embed AI
assistants that render real, interactive interfaces inside your app. Both surfaces
render as native SwiftUI through BindJS, Metabind's component rendering engine. There
are no web views.

A single package ships three libraries. Import only the ones you need.

## Products

| Library | Use it to |
|---|---|
| `Metabind` | Fetch and render content from Metabind's headless content platform. A SwiftUI view, an async/await GraphQL client, SQLite-backed caching, and real-time updates over WebSocket. |
| `MetabindAssistant` | Drop a conversational AI assistant into your app. `MetabindAssistantView` wires up the language model, Model Context Protocol (MCP) tool calls, and interactive rendering for you. |
| `MCPAppsHost` | Render a single MCP tool result without the conversational layer. The low-level building blocks (`MCPAppsClient`, `MCPAppSession`, `MCPAppView`) that `MetabindAssistant` is built on. |

Metabind is the commercial content platform. BindJS is the open-source framework that
renders its components natively. Your app links BindJS through a precompiled binary, so
the engine is the same one that powers Metabind content in Claude, ChatGPT, and every
other MCP host.

## Requirements

- Swift 5.11 or later
- iOS 17, macOS 14, or visionOS 1
- A Metabind account. Create one at [metabind.ai](https://metabind.ai).

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/metabindai/metabind-apple.git", from: "1.2.10")
]
```

Then add the products you need to your target:

```swift
.target(name: "YourApp", dependencies: [
    .product(name: "Metabind", package: "metabind-apple"),           // content SDK
    .product(name: "MetabindAssistant", package: "metabind-apple"),  // AI assistant
    .product(name: "MCPAppsHost", package: "metabind-apple"),        // low-level rendering
])
```

In Xcode, choose File > Add Package Dependencies, enter the repository URL, and select
the libraries you want.

---

# Metabind: the content SDK

Fetch content from Metabind's headless content platform and render it as native
SwiftUI. Metabind manages both the content and its presentation, so you update layouts
and experiences over the air without shipping a new build.

## Initialize the client

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

Find your organization ID, project ID, and API key in Metabind under Settings > General
and Settings > API Keys.

## Render content with MetabindView

`MetabindView` reads `MetabindClient` from the environment. It fetches, caches, and
renders content, and handles its own loading, error, and success states:

```swift
import SwiftUI
import Metabind

struct ContentScreen: View {
    var body: some View {
        MetabindView(contentId: "cont_123")
    }
}
```

`MetabindView` gives you:

- Automatic loading, error, and success states.
- SQLite-backed caching with cache-then-network updates.
- Optional real-time subscriptions over WebSocket.
- A task lifecycle tied to the view, so requests cancel automatically.

## Real-time updates

Set `enableSubscription` to `true` to keep a view in sync with Metabind:

```swift
MetabindView(contentId: "cont_123", enableSubscription: true)
```

The view runs the content stream for the initial load and a WebSocket subscription for
live updates. When you publish a change in Metabind, the view updates in place.

## Working with the API directly

For more control, call the `MetabindClient` APIs yourself. Every resource follows the
same three-method pattern:

- `fetch*()` runs a single async/await request.
- `stream*()` returns an `AsyncStream` that yields cached data first, then network updates.
- `subscribeTo*()` opens a real-time WebSocket subscription. (Content only.)

For the complete API, see the
[Metabind GraphQL documentation](https://docs.metabind.ai/graphql/overview). The schema
also lives in this repository at
[`Sources/Metabind/GraphQL/schema.graphqls`](Sources/Metabind/GraphQL/schema.graphqls).

### Content

Fetch and display individual content entries:

```swift
// Fetch a single content entry
let content = try await client.fetchContent(id: "cont_123")

// Stream content (cache, then network)
for await result in client.streamContent(id: "cont_123") {
    switch result {
    case .success(let content):
        // Update the UI
    case .failure(let error):
        // Handle the error
    }
}

// Subscribe to real-time updates
for await result in client.subscribeToContent(id: "cont_123") {
    switch result {
    case .success(let content):
        // Handle the live update
    case .failure(let error):
        // Handle the error
    }
}
```

### Contents (list)

Fetch paginated lists of content, with filtering and sorting:

```swift
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

// Stream the list
for await result in client.streamContents(typeId: "type_123", tags: ["featured"]) {
    // Handle updates
}
```

### Components

Fetch component definitions:

```swift
let component = try await client.fetchComponent(id: "comp_123")

let components = try await client.fetchComponents(
    search: "Button",
    cursor: nil,
    limit: 20
)

for await result in client.streamComponents(search: "Card") {
    // Handle updates
}
```

### Content types

Fetch content type schemas:

```swift
let contentType = try await client.fetchContentType(id: "type_123")
let schema = try contentType.parsedSchema()  // Parse the schema JSON

let contentTypes = try await client.fetchContentTypes(
    search: "Article",
    cursor: nil,
    limit: 20
)

for await result in client.streamContentTypes() {
    // Handle updates
}
```

### Assets

Fetch media assets such as images, videos, and files:

```swift
let asset = try await client.fetchAsset(id: "asset_123")

let assets = try await client.fetchAssets(
    type: "image/jpeg",           // Filter by MIME type
    tags: ["hero", "banner"],     // Filter by tags
    search: "logo",               // Text search
    filter: AssetFilter(...),     // Advanced filtering
    sort: [SortCriteria(...)],    // Sorting
    cursor: nil,
    limit: 20
)

for await result in client.streamAssets(type: "image/png") {
    // Handle updates
}
```

### Tags

Fetch the tags that organize content and assets:

```swift
let tag = try await client.fetchTag(id: "tag_123")

let tags = try await client.fetchTags(
    search: "category",
    cursor: nil,
    limit: 20
)

for await result in client.streamTags() {
    // Handle updates
}
```

### Packages

Fetch published component packages, which are versioned snapshots:

```swift
let package = try await client.fetchPackage(version: "1.0.0")

let packages = try await client.fetchPackages(
    cursor: nil,
    limit: 20
)

for await result in client.streamPackages() {
    // Handle updates
}
```

### Saved searches

Run searches you configured in Metabind:

```swift
let savedSearch = try await client.fetchSavedSearch(id: "search_123")

let savedSearches = try await client.fetchSavedSearches(
    type: .case(.CONTENT),  // or .ASSET
    cursor: nil,
    limit: 20
)

// Run a saved search and get its results
let results = try await client.executeSavedSearch(
    id: "search_123",
    cursor: nil,
    limit: 20
)

// Results are a union of ContentList or AssetList
if let contentList = results.asContentList {
    let contents = contentList.data
} else if let assetList = results.asAssetList {
    let assets = assetList.data
}
```

## Direct rendering with BindJSView

For advanced cases, fetch content and render it with `BindJSView`:

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

## Parse content data

Extract structured data from content for your own logic:

```swift
let content = try await client.fetchContent(id: "cont_123")

// Parse the content JSON into a PropertyValue map
let propertyMap = try content.parsedContent()

// Access nested data
let title = propertyMap["title"]?.string
let items = propertyMap["items"]?.array
let metadata = propertyMap["metadata"]?.object
```

## Cache policies

Control caching with `CachePolicy`:

| Policy | Behavior | Use it for |
|---|---|---|
| `.fetchIgnoringCacheData` | Always fetch from the network | The default for `fetch*()` methods |
| `.returnCacheDataDontFetch` | Return cached data only | Offline mode, instant display |
| `.returnCacheDataAndFetch` | Yield cache, then network | `stream*()` methods only |
| `.returnCacheDataElseFetch` | Cache if available, otherwise network | Avoid with `fetch*()` |

```swift
// Force a network fetch
let content = try await client.fetchContent(
    id: "cont_123",
    cachePolicy: .fetchIgnoringCacheData
)

// Use the cache only, for instant display
let cached = try await client.fetchContent(
    id: "cont_123",
    cachePolicy: .returnCacheDataDontFetch
)
```

## Error handling

```swift
do {
    let content = try await client.fetchContent(id: "cont_123")
} catch MetabindClientError.noData {
    // Content not found
} catch MetabindClientError.graphQLErrors(let messages) {
    // GraphQL errors, such as validation or permissions
    print("Errors: \(messages)")
} catch MetabindClientError.missingResolvedPackage {
    // Package resolution failed
} catch MetabindClientError.invalidComponentsJSON {
    // Package component parsing failed
} catch {
    // Network or other errors
}
```

---

# MetabindAssistant: the AI assistant SDK

Embed a Metabind AI assistant in your app, one that calls real tools and renders real
interactive UI as native SwiftUI, governed by the same MCP App you publish to Claude,
ChatGPT, and every other MCP host. A single MCP App definition powers two surfaces: a
hosted MCP server that every AI host can discover, and a drop-in native assistant inside
your own app. `MetabindAssistant` handles the second.

When an MCP App returns a `ui` resource, the SDK fetches the BindJS bundle and renders it
as native SwiftUI, the same interface a person sees in Claude or ChatGPT, running
natively inside your app. Format negotiation is automatic: on the MCP `initialize`
handshake, the client advertises the MIME types its registered `ContentResolver`s
support (`application/vnd.bindjs+json` for native rendering, `text/html;profile=mcp-app`
as a fallback) through the `io.modelcontextprotocol/ui` capability extension. The server
picks the right bundle format for each call, so you never set `Accept` headers yourself.

## Quick start: Agent proxy

`MetabindAgentProvider` routes the conversation through `agent.metabind.ai`. The proxy
holds your language model credentials server-side, runs the tool-use loop, and streams
normalized events back. Your app ships no Anthropic or OpenAI keys:

```swift
import SwiftUI
import MetabindAssistant

struct ContentView: View {
    @State private var assistant = MetabindAssistant(
        serverURL: URL(string: "https://mcp.metabind.ai/<org>/projects/<project>")!,
        serverHeaders: ["authorization": "Bearer \(metabindApiKey)"],
        provider: MetabindAgentProvider(
            apiKey: metabindApiKey,
            orgId: "<org>",
            projectId: "<project>"
        )
    )

    var body: some View {
        MetabindAssistantView(assistant: assistant)
    }
}
```

One Metabind API key authenticates both the MCP server and the agent proxy. Create one
in Metabind, or with `metabind api-key create`.

## Quick start: Anthropic (BYOK)

To run the tool-use loop on device against your own Anthropic key, swap the provider:

```swift
@State private var assistant = MetabindAssistant(
    serverURL: URL(string: "https://mcp.metabind.ai/<org>/projects/<project>")!,
    serverHeaders: ["authorization": "Bearer \(mcpBearer)"],
    provider: AnthropicProvider(apiKey: anthropicKey)
)
```

Same view, same observable surface, a different conversation engine.

## Build a custom UI

`MetabindAssistant` is `@Observable`. Its `conversation`, `isProcessing`, `tools`, and
`pendingContext` are all observable, so you can build an entirely custom interface
instead of using `MetabindAssistantView`.

## useMCPHost: components calling back into your app

BindJS components rendered inside a tool result reach host capabilities through
`useMCPHost()`:

```js
// inside a BindJS component
const host = useMCPHost()
if (host) {
    const { products } = await host.toolCall('search_products', { query })
    await host.updateModelContext({ selectedProduct: products[0] })
    await host.sendMessage('Tell me more about this one')
    const answer = await host.elicit(
        { type: 'object', properties: { email: { type: 'string' } } },
        { title: 'Sign up for updates' }
    )
}
```

When you use `MetabindAssistant`, `assistant.hostBridge` is pre-wired, so components see:

- `toolCall(name, args)` runs a tool through the MCP server and returns unwrapped
  structured data.
- `sendMessage(text)` injects a new user turn into the conversation.
- `updateModelContext(dict)` buffers structured context as a `<context>{…}</context>`
  prefix on the next user turn. The visible chat bubble stays clean.
- `log(level, message, data)` routes through `os.Logger`, subsystem
  `MetabindAssistant.Host`.

`MetabindAssistantView` also wires `openLink(url)` to SwiftUI's `@Environment(\.openURL)`.

Fill in the rest by setting handlers on `assistant.hostBridge.handlers`:

```swift
.task {
    assistant.hostBridge.handlers.onElicit = { schema, metadata in
        // Present a SwiftUI sheet derived from `schema`
        return ElicitationResponse(action: .accept, content: [...])
    }
    assistant.hostBridge.handlers.onDisplayMode = { requested in
        return .fullscreen
    }
}
```

For an app that uses `MCPAppView` on its own, without the assistant, build a bridge and
inject it directly:

```swift
MCPAppView(session: session)
    .mcpHostBridge(myBridge)
```

---

# MCPAppsHost: low-level rendering

Render a single tool result without the conversational wrapper:

```swift
import SwiftUI
import MCPAppsHost

struct ContentView: View {
    let client = MCPAppsClient(
        url: URL(string: "https://your-mcp-server.example.com")!,
        headers: ["authorization": "Bearer \(token)"]
    )

    @State private var session: MCPAppSession?

    var body: some View {
        VStack {
            Button("Launch tool") {
                let call = SimpleMCPToolCall(
                    id: UUID().uuidString,
                    name: "create_promotion",
                    arguments: .object([:])
                )
                session = MCPAppSession(toolCall: call, server: client)
            }
            if let session {
                MCPAppView(session: session)
            }
        }
    }
}
```

---

# Samples

Three sample apps live in [`Samples/`](Samples). Each references this package locally, so
you can open one, build it, and see the SDK working against the current source.

| Sample | Shows |
|---|---|
| [Retail](Samples/MetabindContent/Retail) | A minimal `Metabind` integration: initialize the client, render content, and route between pages. |
| [Spotlight](Samples/MetabindContent/Spotlight) | A richer `Metabind` integration: multiple content blocks, real-time updates, push notifications, and deep links. Includes a full account-setup guide. |
| [AssistantDemo](Samples/MetabindAI/AssistantDemo) | A `MetabindAssistant` chat app whose tool returns render as live, native SwiftUI. About 20 lines of integration code. |

To use a sample outside this repository, change its package reference from the local path
to the published package URL, `https://github.com/metabindai/metabind-apple`.

# Logging

Every layer logs through `os.Logger`:

| Subsystem | Category | Contents |
|---|---|---|
| `MetabindAssistant` | `Assistant` | Conversation lifecycle, tool discovery, loop iterations |
| `MetabindAssistant` | `AgentProxy` | Server-sent events from the Metabind agent service |
| `MetabindAssistant` | `Anthropic` | Anthropic BYOK provider stream |
| `MetabindAssistant` | `Host` | Component-originated host calls (`useMCPHost`) |
| `MCPAppsHost` | `MCPAppSession` | Session phase transitions, resource fetching |
| `MCPAppsHost` | `MCPAppsClient` | MCP JSON-RPC requests and responses |
| `MCPAppsHost` | `MCPAppContent` | Per-render BindJS argument keys |
| `BindJS` | `Runtime` | JavaScript exceptions and `console.log` output from components |

View them in Console, or tail them from the command line:

```bash
log show --info --debug --last 5m \
  --predicate 'subsystem BEGINSWITH "MetabindAssistant" OR subsystem == "MCPAppsHost" OR subsystem == "BindJS"'
```

# Regenerating GraphQL code

The GraphQL schema, operations, and `apollo-codegen-config.json` live in
[`Sources/Metabind/GraphQL/`](Sources/Metabind/GraphQL). Run codegen from that directory
so the config's relative paths resolve correctly:

```bash
cd Sources/Metabind/GraphQL
apollo-ios-cli generate
```

Generated code is written to `Sources/Metabind/generated/`. Never edit those files by
hand.

# Dependencies

- Apollo iOS 1.23.0, the GraphQL client, with WebSocket and SQLite support. Used by
  `Metabind`.
- BindJS, the component rendering engine, linked through the precompiled
  `bindjs-apple-binary` package. Used by all three libraries.

# License

Copyright © 2026 Yap Studios LLC. All rights reserved. See [`LICENSE`](LICENSE).
