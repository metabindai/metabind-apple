# Metabind Assistant Demo (Apple)

A SwiftUI chat app that shows what [`MetabindAssistant`](https://github.com/metabindai/metabind-apple) — Metabind's drop-in conversational AI view — feels like in practice.

Paste a Metabind API key, hit Start, and chat with an assistant whose tool returns render as live, native SwiftUI.

## What it does

1. Prompts for your Metabind API key on first launch and stores it in the macOS Keychain.
2. Connects to the Metabind Agent proxy (`agent.metabind.ai`) and the Oak & Ivory demo project's MCP server.
3. Streams assistant responses, executes MCP tool calls server-side, and renders the returned `ui` resources as native SwiftUI via BindJS.

No LLM provider keys ship in the binary — the agent proxy holds the upstream credentials and runs the tool-use loop. One Metabind API key authenticates both the MCP server and the agent.

Total integration code: **~20 lines of Swift**.

## Requirements

- macOS 14+ with Xcode 16
- A Metabind API key — create one at [metabind.ai](https://metabind.ai) or via the CLI: `metabind api-key create --name demo`

## Run

```sh
open MetabindAssistantDemo.xcodeproj
```

Or build it as a Swift package executable:

```sh
swift run MetabindAssistantDemo
```

Paste your Metabind API key into the launch screen, hit Start, then try:

- "Show me a sofa, then a matching armchair"
- "Compare two of your bestselling sofas"
- "Build a mood board for a Japandi living room"

Each tool call streams text and renders an interactive product component inline.

## How it works

The integration lives in [`Sources/MetabindAssistantDemo/ContentView.swift`](Sources/MetabindAssistantDemo/ContentView.swift):

```swift
let provider = MetabindAgentProvider(
    baseURL: MetabindAgentProvider.productionHost,
    apiKey: metabindApiKey,
    orgId: orgId,
    projectId: projectId
)
assistant = MetabindAssistant(
    serverURL: mcpServerURL,
    serverHeaders: ["authorization": "Bearer \(metabindApiKey)"],
    provider: provider
)
```

Then:

```swift
MetabindAssistantView(assistant: assistant)
```

That's the whole integration. `MetabindAssistant` handles tool discovery, the (server-side) conversation loop, streaming, and interactive rendering via BindJS.

## Where to next

- [Metabind for Apple](https://github.com/metabindai/metabind-apple) — the SDK this app uses, with BYOK setup and lower-level `MCPAppsHost` building blocks.
- [Metabind](https://metabind.ai) — build your own MCP App in MCP App Studio.

## License

MIT. See [`LICENSE`](LICENSE).
