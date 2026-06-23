// MCPAppsHost — Native MCP Apps for iOS
//
// Architecture:
//   Conversation Engine (model layer)
//     └─ MCPAppSession             ← you own this, it outlives views
//          └─ MCPAppView           ← attaches to render, detaches on scroll
//               └─ MCPAppContent   ← the rendered BindJS or HTML view
//
// Three levels of control:
//   MCPAppView(session:)                          ← automatic rendering
//   MCPAppView(session:content:placeholder:)      ← customize content + loading
//   MCPAppView(session:) { phase in ... }         ← full phase control
//
// Two session types:
//   MCPAppSession          ← framework executes the tool
//   ManualMCPAppSession    ← you execute the tool

// All public types are exported from their individual files.
// This file exists for documentation and module-level re-exports.

@_exported import BindJS
