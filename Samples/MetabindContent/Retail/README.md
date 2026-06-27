# Metabind Sample Retail

A minimal SwiftUI sample app demonstrating how to integrate the Metabind SDK into an iOS application.

## Overview

This project provides a starting point for building iOS apps with server-driven UI powered by Metabind. It shows the essential steps for initializing the Metabind client, displaying content, and handling navigation between pages.

## Requirements

- Xcode 15.0 or later
- iOS 17.0 or later
- A Metabind account with valid API credentials

## Getting Started

1. Clone or download this repository.
2. Open `MetabindSampleRetail.xcodeproj` in Xcode.
3. In `MetabindSampleRetailApp.swift`, replace the placeholder values with your credentials from the [Metabind dashboard](https://metabind.ai):
   - `apiKey`
   - `organizationId`
   - `projectId`
   - `contentId` (for your root content page)
4. Build and run the app on a simulator or device.

## Project Structure

```
MetabindSampleRetail/
├── MetabindSampleRetailApp.swift   # App entry point and main content view
└── Assets.xcassets/                # App icons and colors
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

Copyright © 2026 Yap Studios LLC. All rights reserved. See [`LICENSE`](LICENSE).
