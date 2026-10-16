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

On 2026-10-02, the production endpoint passed `LiveBindJSViewTests` anonymously with the default new MIME type. The test discovered a BindJS View, resolved its integrity-checked package, constructed its native BindJS component tree and SwiftUI view, and read the separately negotiated HTML representation. No tools were called and no project content was changed. This October 2 run was a programmatic rendering check. The simulator walkthrough below supplements it.

The prior deployment's legacy-only listing/CDN failure is resolved. Relevant backend View-channel E2E fixes were merged in `metabind-mcp` PR #271 on September 30; production release v1.0.20 followed October 1.

The dev environment check remains pending dev login access. Its earlier anonymous request returned HTTP 401, and CLI login required browser reauthorization. Production coverage does not satisfy the ticket's explicit dev-environment acceptance check.

`LiveBindJSViewTests` is an opt-in, read-only check. It lists/reads resources, resolves verified sources, creates a native view tree, and requests the separately negotiated HTML representation. It never calls a tool. Run it with:

```sh
MCP_APPS_TEST_URL='https://mcp-dev.metabind.ai/ORG/projects/PROJECT' \
MCP_APPS_TEST_TOKEN_FILE='/path/to/local/token-file' \
swift test --filter LiveBindJSViewTests
```

The expected MIME type defaults to `application/bindjs+json`. For legacy compatibility checks only, set `MCP_APPS_TEST_MIME=application/vnd.bindjs+json`. Token contents are read from the local file, never placed in command arguments or committed.

## iOS simulator validation — 2026-10-16

An external validation app linked directly to SDK commit `c86b3de`, using BindJS 1.2.0, ran on an iPhone 17 Pro simulator with iOS 26.5 (23F77). It hosted the published Finance cards with `MCPAppView` and `MetabindHostBridge`; data calls went to the real production project. This tested SDK rendering and interactions, not the full conversational app or an LLM turn.

- Visually checked subscriptions, spending breakdown, net-worth chart, and transactions.
- The subscriptions Price rises filter narrowed the list from eight to two. The ClassPass Charge history action delivered the expected follow-up message to the host. Transactions Largest sorting changed the list to descending amounts.
- The actual default `PackageHTTPTransport.session` downloaded the 301,508-byte production package, matching its published SHA-256. A subsequent process (PID 91394, following PID 91324) loaded it with URLSession metrics reporting `localCache`, zero request bytes, and zero received network bytes. The same result held after a full simulator shutdown/boot (PID 91741). Its URL was present in the on-disk URLCache database.
- A loopback fixture served the same bytes with controlled cache headers through the same default session. The fresh `max-age=3600` response reached the origin once across all launches. After `max-age=15` expired, the new process sent the ETag validator, received HTTP 304, and recovered the exact stored body. `no-cache` revalidated; `no-store` downloaded again and had no disk-cache entry.
- A test-only `Cache-Control: no-cache` request to the real production URL also produced HTTP 304 with zero response-body network bytes and the correct recovered body. This deliberately forced revalidation; natural production expiry was not observed.
- The production package response had ETag and Last-Modified, but no Cache-Control or Expires. It was reused by Foundation in this test; its freshness duration is not explicitly specified by the server. Explicit server cache headers remain worth confirming for the deployed package path.
- Dev was rechecked: anonymous access returned HTTP 401 and the saved CLI login refresh returned AUTH_FAILED. The dev acceptance check remains blocked on access and project confirmation.

Screenshots, the external host source, URLSession metrics, origin request logs, and assertions are retained outside the SDK repository. No SDK implementation changes were needed, and no project content was modified. Physical-device behavior and the complete chat flow were not tested in this run.
