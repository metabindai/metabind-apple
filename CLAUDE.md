# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The Metabind Apple SDK — one Swift Package, three products you can adopt independently. Metabind is the hosted platform for MCP Apps; this SDK embeds the governed agent inside an iOS, macOS, or visionOS app and renders Metabind-managed content as native SwiftUI.

| Product | Purpose | Direct dependencies |
|---|---|---|
| `MetabindContent` | Content SDK: `MetabindView`, async/await GraphQL client (Apollo), SQLite caching, WebSocket subscriptions | Apollo iOS, BindJS |
| `MCPAppsHost` | Low-level rendering of a single MCP tool result as SwiftUI (`MCPAppsClient`, `MCPAppSession`, `MCPAppView`) | BindJS |
| `MetabindAI` | Assistant SDK: `MetabindAssistant` + `MetabindAssistantView` drop-in conversational surface, with the Metabind Agent proxy or BYOK Anthropic | `MCPAppsHost` |

Platforms: iOS 17+, macOS 14+, visionOS 1+. Swift tools 5.11. License: Apache 2.0 (`LICENSE`, `NOTICE`).

Preserve the dependency boundaries in `Package.swift`: `MCPAppsHost` links only BindJS (no Apollo), `MetabindAI` depends only on `MCPAppsHost`, and `MetabindContent` is the only target that touches Apollo. Integrators link each library separately, so don't couple them.

The [README](README.md) is the public integration guide — installation, quick starts, the full `MetabindClient` API surface, cache policies, and error handling. Keep it accurate when you change public behavior; don't duplicate its content here.

## Commands

```bash
swift build                              # Build all targets
swift test                               # Run MCPAppsHostTests and MetabindAITests
swift test --filter MCPAppsHostTests     # Run one suite
```

`MetabindContent` has no test target. Validate changes there with `swift build` and by running the `Samples/MetabindContent` apps.

## GraphQL codegen (MetabindContent)

The schema, operations, and codegen config live in `Sources/MetabindContent/GraphQL/` (`schema.graphqls`, `Queries.graphql`, `Fragments.graphql`, `Subscriptions.graphql`, `apollo-codegen-config.json`). After changing any of them, regenerate from that directory so the config's relative paths resolve:

```bash
cd Sources/MetabindContent/GraphQL
apollo-ios-cli generate
```

- Generated code lands in `Sources/MetabindContent/generated/` and is checked in. **Never edit files in `generated/` by hand.**
- The `GraphQL/` directory is excluded from the target build (`exclude: ["GraphQL"]` in `Package.swift`); only the generated code compiles. Don't "fix" the exclusion.
- `apollo-ios-cli` is not checked into this repository. Use a CLI build that matches the pinned Apollo iOS version (exactly 1.23.0 in `Package.swift`).

## Dependencies

- **Apollo iOS** — pinned `exact: "1.23.0"`. Version bumps require regenerating GraphQL code with a matching CLI.
- **BindJS** — the rendering engine, linked as the precompiled binary package `metabindai/bindjs-apple-binary` (`from: "1.1.7"`). The engine's source lives in the [`bindjs-apple`](https://github.com/metabindai/bindjs-apple) repository (Apache 2.0); this repo consumes precompiled releases only. To pick up a new BindJS release, bump the version in `Package.swift` and let SwiftPM update `Package.resolved`.
- **GLTFKit2** appears in `Package.resolved` as a transitive dependency of BindJS (3D model support). Don't declare it directly.

## Samples

Three Xcode projects under `Samples/`, grouped by the product they demonstrate:

| Sample | Shows |
|---|---|
| `Samples/MetabindContent/Retail` | Minimal `MetabindContent` integration: client setup, content rendering, page navigation |
| `Samples/MetabindContent/Spotlight` | Richer `MetabindContent` integration: multiple content blocks, real-time updates, push notifications, deep links |
| `Samples/MetabindAI/AssistantDemo` | `MetabindAI` chat app (macOS) whose tool returns render as live SwiftUI, via the agent proxy |

Each project references this package by local path (`XCLocalSwiftPackageReference` pointing at `../../..`), so building a sample compiles the SDK from your current checkout — the fastest way to see a source change running in a real app. Open the sample's `.xcodeproj`; each sample has its own README with account and credential setup.

## Conventions

- **Logging** goes through `os.Logger`. Subsystem `MetabindAssistant` (categories `Assistant`, `AgentProxy`, `Anthropic`, `Host`) for `MetabindAI`; subsystem `MCPAppsHost` (categories `MCPAppSession`, `MCPAppsClient`, `MCPAppContent`) for the host layer; the BindJS binary logs under subsystem `BindJS`, category `Runtime`. Add new loggers under the existing subsystem for the target you're in. The README's "Logging" section has the `log show` command for tailing all three.
- **State** uses the Observation framework: `MetabindAssistant`, `MetabindClient`, and `MCPAppSession` are `@Observable`, and clients are injected with `.environment(...)`. Don't introduce `ObservableObject` or Combine.
- **Docs language**: the agent is *governed* (never "autonomous"), the conversational product is the *Assistant SDK*, and the native-rendering claim is scoped — BindJS renders SwiftUI here, not web views.
