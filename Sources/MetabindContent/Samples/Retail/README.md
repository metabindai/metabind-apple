# Metabind Sample Retail

A minimal SwiftUI sample app demonstrating how to integrate the Metabind SDK into an iOS application.

## Overview

This project provides a starting point for building iOS apps whose content and UI update instantly from Metabind — publish a change and it's live in the app, no release required. It shows the essential steps for initializing the Metabind client, displaying content, and handling navigation between pages.

## Requirements

- Xcode 26.2 or later
- iOS 26.2 or later (the sample project's deployment target)
- A Metabind account with valid API credentials

## Getting Started

1. Clone or download this repository.
2. Open `MetabindSampleRetail.xcodeproj` in Xcode.
3. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, then fill in your API key, organization ID, project ID, and published root content ID from the [Metabind dashboard](https://metabind.ai). This file is ignored by Git; keep real credentials out of Swift source and the example file.
4. Build and run the app on a simulator or device.

Both build configurations read `Config/Local.xcconfig` through `RetailSample.xcconfig`. Xcode places these values in the app's Info.plist for the sample to read. Rebuild after changing the configuration.

Use a restricted demo key with `read:content`, `read:types`, `read:packages`, `read:components`, and `read:assets`. The key is embedded in the built app; keep private test builds and credentials out of distribution.

## Project Structure

```
Config/
├── RetailSample.xcconfig           # Public defaults and local config include
├── Local.xcconfig.example          # Copy to ignored Local.xcconfig
└── Info.plist                      # Build-setting placeholders
MetabindSampleRetail/
├── MetabindSampleRetailApp.swift    # App entry point and main content view
└── Assets.xcassets/                 # App icons and colors
```

## Key Concepts

### Client Initialization

The `MetabindClient` is initialized with your API credentials and injected into the SwiftUI environment:

```swift
@State var client = MetabindClient(
    url: URL(string: "https://api.metabind.ai/graphql")!,
    ws: URL(string: "wss://ws-api.metabind.ai")!,
    apiKey: "your-api-key",
    organizationId: "your-org-id",
    projectId: "your-project-id"
)
```

### Displaying Content

Use `MetabindView` to render content by its ID:

```swift
MetabindView(contentId: "your-content-id")
```

### Handling Navigation

Listen for `metabind.content` actions to navigate between content pages:

```swift
.onMetabindAction { action in
    if action.name == "metabind.content",
       let contentId = action.props["contentId"] as? String {
        path.append(Destination.content(id: contentId))
    }
}
```

## Resources

- [Metabind Documentation](https://docs.metabind.ai)
- [Metabind Dashboard](https://metabind.ai)

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
