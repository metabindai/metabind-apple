# Metabind Finance Demo (Apple)

A SwiftUI banking app with no chat in it, built entirely on [`MetabindAssistant`](../../..) — Metabind's conversational AI engine.

Every screen is an LLM answer. The app asks one question on launch and its rendered MCP result *is* the home screen; further questions come from a pill rail at the bottom and are answered in a sheet on top. There's no transcript, no navigation stack, and you never leave the home screen.

## What it does

1. Prompts for your Metabind API key on first launch and stores it in the Keychain.
2. Connects to the Metabind Agent proxy (`agent.metabind.ai`) and the Vault (banking assistant) demo project's MCP server.
3. Streams assistant responses, executes MCP tool calls server-side, and renders the returned `ui` resources as native SwiftUI via BindJS.
4. Routes each turn to a surface instead of a message list — see [`AnswerRouter`](Sources/MetabindFinanceDemo/AnswerRouter.swift).

No LLM provider keys ship in the binary — the agent proxy holds the upstream credentials and runs the tool-use loop. One Metabind API key authenticates both the MCP server and the agent.

The connection is still ~20 lines of Swift. Everything else is app UI.

## Requirements

- iOS 17+ (the ask bar renders as Liquid Glass on iOS 26, with a material fallback on earlier systems)
- Xcode 26
- A Metabind API key — create one at [metabind.ai](https://metabind.ai) or via the CLI: `metabind api-key create --name demo`

## Run

```sh
open MetabindFinanceDemo.xcodeproj
```

The project references the SDK package by local path, so building it compiles the SDK from your current checkout. To use it outside this repository, change the package reference to the published URL, `https://github.com/metabindai/metabind-apple`.

Paste your Metabind API key into the launch screen and hit Start. The home
screen loads itself by asking *"Where did my money go this month?"*; tap a pill
to ask another, or "Ask anything" to type your own.

## How it works

The integration lives in [`Sources/MetabindFinanceDemo/ContentView.swift`](Sources/MetabindFinanceDemo/ContentView.swift):

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

`MetabindAssistant` handles tool discovery, the (server-side) conversation loop,
streaming, and interactive rendering via BindJS. The quickest way to use it is the
drop-in chat view:

```swift
MetabindAssistantView(assistant: assistant)
```

This demo skips that and builds its own UI on the same object, which is the point
of it. `assistant.conversation.messages` is observable, so
[`AnswerRouter`](Sources/MetabindFinanceDemo/AnswerRouter.swift) reads it and
decides where each turn lands — the tool sessions render through `MCPAppView`
exactly as they would in chat.

Two things a custom UI has to do that the chat view does for you:

- Wire the host bridge handlers that need SwiftUI environment (`onOpenLink`,
  `onDisplayMode`) — see `HomeView.wireHostBridge()`.
- Wait for `session.awaitResult()` before presenting. A tool session is appended
  the moment the model *starts* the call, so rendering it immediately shows an
  empty card.

## Where to next

- [Metabind for Apple](../../..) — the SDK this app uses, with BYOK setup and lower-level `MCPAppsHost` building blocks.
- [AssistantDemo](../AssistantDemo) — the same engine behind the drop-in `MetabindAssistantView` chat surface.
- [Metabind](https://metabind.ai) — build your own MCP App in MCP App Studio.

## License

MIT. See [`LICENSE`](LICENSE).
