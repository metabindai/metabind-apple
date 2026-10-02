# MET-1486 validation

Worktree: `metabind-apple.worktrees/met-1486`.
Branch: `feature/MET-1486-bindjs-view`, based on `main` at `c2e1ea0` (MCP 2026-07-28 support included).

## Implemented

- Advertise the BindJS 1.0 View type alongside legacy BindJS and HTML.
- Preserve resource metadata and paginate resource discovery. Share concurrent discovery, honor modern listing TTLs, and invalidate legacy listings on cache reset or reconnection.
- Prefetch referenced packages once per batch while retaining HTTP freshness checks during rendering.
- Fetch referenced packages over HTTPS, falling back to MCP resource reads on transport failure.
- Verify SHA-256 and UTF-8 byte length before using component sources.
- Let URLSession/URLCache control HTTP freshness on every package load. The digest cache only avoids repeated JSON decoding; no-store also disables that cache.
- Request HTML on a separate negotiated connection when a View is rejected.

Scope is the deployed referenced-package View representation. Inline packages and dependencies fail closed to HTML; the content channel is not advertised.

## Local validation — 2026-10-02

- Complete `swift test` passed: 74 MetabindAI tests and 179 MCPAppsHost tests reported, with the two environment-gated live tests skipped. The View live test was also run separately and passed, as described below.
- Real loopback HTTP server tests verify fresh max-age reuse, expired max-age revalidation, no-cache ETag/304 handling, and no-store. These exercise Foundation HTTP caching, not a simulated cache in URLProtocol.
- Resolver tests cover UTF-8 package integrity, content/listing metadata precedence, CDN failure, corrupt bytes even with a warm decoded cache, HTTPS requirements, unsupported documents, HTML fallback, and construction of a native view tree with BindJSContext.
- Client tests cover listing pagination, concurrent discovery, modern TTLs and malformed responses, reconnection invalidation, package prefetch deduplication, package cache bypass, metadata propagation, and separate HTML/native session negotiation.
- AssistantDemo iOS Simulator build passed with the modified SDK on current main.

## Live validation

The Finance QR project is the production Banking Assistant (`finance-app`) in Metabind:
`IgJH0BzIn4LlfnCbcDc7 / GLbHk5i3GLlIYcF63XFl`.

On 2026-10-02, the production endpoint passed `LiveBindJSViewTests` anonymously with the default new MIME type. The test discovered a BindJS View, resolved its integrity-checked package, constructed its native BindJS component tree and SwiftUI view, and read the separately negotiated HTML representation. No tools were called and no project content was changed. This is a programmatic rendering check, not a visual device walkthrough.

The prior deployment's legacy-only listing/CDN failure is resolved. Relevant backend View-channel E2E fixes were merged in `metabind-mcp` PR #271 on September 30; production release v1.0.20 followed October 1.

The dev environment check remains pending dev login access. Its earlier anonymous request returned HTTP 401, and CLI login required browser reauthorization. Production coverage does not satisfy the ticket's explicit dev-environment acceptance check.

`LiveBindJSViewTests` is an opt-in, read-only check. It lists/reads resources, resolves verified sources, creates a native view tree, and requests the separately negotiated HTML representation. It never calls a tool. Run it with:

```sh
MCP_APPS_TEST_URL='https://mcp-dev.metabind.ai/ORG/projects/PROJECT' \
MCP_APPS_TEST_TOKEN_FILE='/path/to/local/token-file' \
swift test --filter LiveBindJSViewTests
```

The expected MIME type defaults to `application/bindjs+json`. For legacy compatibility checks only, set `MCP_APPS_TEST_MIME=application/vnd.bindjs+json`. Token contents are read from the local file, never placed in command arguments or committed.
