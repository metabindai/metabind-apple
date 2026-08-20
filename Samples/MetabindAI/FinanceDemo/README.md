# Metabind Finance Demo (Apple)

A configurable SwiftUI reference app built on
[`MetabindAssistant`](../../..), Metabind's governed conversational AI
runtime.

The app asks one question on launch and uses the rendered MCP result as its
home screen. Later questions come from the pill rail at the bottom and open in
a sheet. There is no transcript and no navigation stack: assistant turns are
routed to purpose-built surfaces instead of a message list.

## Data and backend

This repository contains the Apple client, not the Finance MCP project or its
data. Before running the app, clone or import the Finance MCP project into your
own Metabind organization and configure this client with that organization's
stable internal ID and the cloned project's ID.

The supplied Finance MCP project uses synthetic financial data, such as sample
transactions, spending categories, balances, and net-worth history. The app
does not connect to real financial accounts unless you replace that backend
with one that does. The agent should explain and render data returned by the
MCP tools rather than inventing financial records.

## What it does

1. Connects to the Metabind Agent proxy and your Finance project's MCP server.
2. Streams governed assistant responses and renders MCP App tool results as
   native SwiftUI through BindJS.
3. Displays partial and multiple tool results as they become available.
4. Routes each turn to a UI surface through
   [`AnswerRouter`](Sources/MetabindFinanceDemo/AnswerRouter.swift).
5. Stores a user-entered or configured Metabind API key in Keychain.

The Metabind Agent proxy holds the upstream model-provider credentials and runs
the tool-use loop. The app never needs an Anthropic or other LLM provider key.
One Metabind API key authenticates both the agent proxy and MCP server.

## Requirements

- iOS 17+
- Xcode 26+
- A Finance MCP project cloned into your own Metabind organization
- A Metabind API key authorized for that organization and project

## Configure a local build

Copy the public template to the ignored local configuration file:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Fill in the values:

```xcconfig
FINANCE_DEMO_BUNDLE_ID = com.yourcompany.MetabindFinanceDemo
FINANCE_DEMO_ORG_ID = your_stable_internal_org_id
FINANCE_DEMO_PROJECT_ID = your_project_id
FINANCE_DEMO_API_KEY =
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

- `FINANCE_DEMO_ORG_ID` must be the stable internal ID, not an organization
  slug.
- `FINANCE_DEMO_API_KEY` is optional for local development. Leave it empty to
  enter the key on first launch. Set it only for a controlled demo build that
  should start without setup.
- `FINANCE_DEMO_BUNDLE_ID` and `DEVELOPMENT_TEAM` are required for a signed
  device or distribution build. The public defaults remain generic.

`Config/Local.xcconfig` is gitignored. Do not commit it.

> [!WARNING]
> A value supplied through `FINANCE_DEMO_API_KEY` is compiled into the app's
> `Info.plist` before being copied to Keychain. Marking the Xcode Cloud variable
> as secret protects build logs and configuration, but it does not make the key
> secret inside a distributed app. Use only a restricted, revocable demo key.
> For a production app, issue short-lived user credentials from a backend
> instead of embedding a shared key.

## Run

```sh
open MetabindFinanceDemo.xcodeproj
```

The project references the SDK package by local path, so building it compiles
the SDK from the current checkout. To use the sample outside this repository,
change the package reference to:

```text
https://github.com/metabindai/metabind-apple
```

If no API key is configured, enter one on the launch screen and tap **Start**.
The home screen loads by asking _"Where did my money go this month?"_. Tap a
suggested follow-up or **Ask anything** to start another turn.

The key is stored as a generic-password Keychain item scoped by the app's bundle
identifier. Keychain items generally survive app deletion. Use
**More (...) > Reset API Key** to remove the stored key. A stored key takes
precedence over a newly configured key, so reset it after rotating credentials.

## Xcode Cloud and TestFlight

The checked-in
[`ci_scripts/ci_post_clone.sh`](ci_scripts/ci_post_clone.sh) generates the
gitignored `Config/Local.xcconfig` on the cloud worker. Configure these workflow
environment variables:

| Variable | Purpose |
|---|---|
| `FINANCE_DEMO_BUNDLE_ID` | Bundle ID registered in Apple Developer and App Store Connect |
| `FINANCE_DEMO_ORG_ID` | Stable internal Metabind organization ID |
| `FINANCE_DEMO_PROJECT_ID` | Finance MCP project ID |
| `FINANCE_DEMO_API_KEY` | Restricted demo API key |
| `DEVELOPMENT_TEAM` | Apple Developer team ID |

Mark all private values as **Secret** in Xcode Cloud. The script intentionally
fails early if any required variable is missing rather than producing a
misconfigured TestFlight build.

The project-level `Package.resolved` is checked in because Xcode Cloud archives
with automatic package resolution disabled. Keep it updated when package
dependencies change.

## How it works

The integration lives in
[`ContentView.swift`](Sources/MetabindFinanceDemo/ContentView.swift):

```swift
let provider = MetabindAgentProvider(
    baseURL: MetabindAgentProvider.productionHost,
    apiKey: metabindApiKey,
    orgId: orgId,
    projectId: projectId
)

assistant = MetabindAssistant(
    serverURL: mcpServerURL,
    serverHeaders: ["authorization": "******"],
    provider: provider,
    configuration: .init(prefetchUIResources: true)
)
```

`MetabindAssistant` handles tool discovery, the server-side conversation loop,
streaming, and interactive rendering. The SDK's drop-in conversational surface
is:

```swift
MetabindAssistantView(assistant: assistant)
```

FinanceDemo instead observes `assistant.conversation.messages` and uses
[`AnswerRouter`](Sources/MetabindFinanceDemo/AnswerRouter.swift) to decide where
each turn lands. Tool sessions render through `MCPAppView`, just as they do in
the drop-in view.

A custom surface must also:

- Wire host-bridge handlers that need SwiftUI environment, such as
  `onOpenLink` and `onDisplayMode`.
- Handle partial tool results and wait until a session has renderable content
  before presenting it.
- Inject `assistant.hostBridge` above any sheet that contains MCP App content.

## Where to next

- [Metabind for Apple](../../..) - SDK installation, API reference, logging,
  BYOK setup, and lower-level `MCPAppsHost` building blocks.
- [AssistantDemo](../AssistantDemo) - the same runtime behind the drop-in
  `MetabindAssistantView` conversational surface.
- [Metabind](https://metabind.ai) - create and manage MCP Apps.

## License

MIT. See [`LICENSE`](LICENSE).
