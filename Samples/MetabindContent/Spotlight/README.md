# Metabind Sample — Spotlight

A SwiftUI sample app showing how to render CMS-managed content natively using the [Metabind](https://metabind.ai) iOS SDK. The guide below walks you through creating a free Metabind account, generating credentials, and connecting the sample to a project you control.

## What This App Demonstrates

- **`MetabindView`** — drop-in SwiftUI view that fetches and renders CMS content by ID
- **Real-time updates** — WebSocket subscriptions so content changes publish instantly, no app update needed
- **Multiple content blocks** — hero banners and info-card rails on the same screen, each fetching independently
- **Push notifications** — local notification that opens a `MetabindView` sheet when tapped
- **Deep-link routing** — CTA buttons in CMS content trigger custom URL schemes the app intercepts

## Requirements

- Xcode 16 or later
- iOS 17.0 or later

## Quick Start

Follow the [setup guide](#getting-your-own-metabind-credentials) below to create a free Metabind account and add your credentials to the app, then:

1. Open `MetabindSampleSpotlight.xcodeproj` in Xcode.
2. Build and run on a simulator or device.

## Getting Your Own Metabind Credentials

You need three values to connect the SDK: an **Organization ID**, a **Project ID**, and an **API Key**.

### 1. Create an Account

1. Go to [metabind.ai/signup](https://metabind.ai/signup).
2. Enter your email. You'll receive a 6-digit verification code.
3. Enter the code, then fill in your name and create a password.

A free tier is available — no credit card required.

### 2. Create Your Organization and Project

After signing up you'll be walked through onboarding:

1. Name your organization and choose a URL slug.
2. Pick a project template (or start blank).
3. Wait a few seconds for provisioning to finish.

You'll land in **Metabind** — the web-based content editor where you create and publish content.

### 3. Find Your Organization ID and Project ID

1. In Metabind, click the **gear icon** (bottom of the left sidebar) to open **Settings**.
2. Select **General**.
3. Scroll to the **SDK** section — your **Project ID** and **Organization ID** are displayed with click-to-copy buttons.

The SDK section also shows a ready-to-use SwiftUI code snippet with your IDs pre-filled.

### 4. Generate an API Key

1. In Settings, select **API Keys** in the left sidebar.
2. Click the **+** button to create a new key.
3. Give it a name (e.g. "iOS Sample").
4. **Copy the key immediately** — it's only shown once.

### 5. Add Your Credentials to the App

Open `MetabindSampleSpotlightApp.swift` and replace the values in the `MetabindClient` initializer:

```swift
@State var client = MetabindClient(
    url: URL(string: "https://api.metabind.ai/graphql")!,
    ws: URL(string: "wss://ws-api.metabind.ai")!,
    apiKey: "YOUR_API_KEY",
    organizationId: "YOUR_ORGANIZATION_ID",
    projectId: "YOUR_PROJECT_ID"
)
```

The `url` and `ws` endpoints stay the same for all projects.

Then inject the client into the SwiftUI environment so `MetabindView` can access it:

```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .environment(client)
    }
}
```

Place `.environment(client)` high in the view hierarchy. Sheets and popovers create a new environment, so inject it again on any presented content:

```swift
.sheet(isPresented: $showDetail) {
    DetailView()
        .environment(client) // sheets need their own injection
}
```

### 6. Create Content and Use It

1. In Metabind, create a piece of content and publish it.
2. Copy the content ID from the inspector panel (it looks like `cont_1772074912950486`).
3. Drop a `MetabindView` anywhere in your SwiftUI hierarchy:

```swift
MetabindView(contentId: "cont_YOUR_CONTENT_ID")
```

That's it. The view handles fetching, caching, and rendering. Add `enableSubscription: true` to get real-time updates when you edit content in Metabind:

```swift
MetabindView(contentId: "cont_YOUR_CONTENT_ID", enableSubscription: true)
```

## How It Works

**1. Compose in Metabind** — Build experiences from native components using the visual editor: text, images, media rails, CTAs, video, 3D models. Content teams use the visual editor. Developers use the code editor for custom components.

**2. Deliver as data** — Component specifications ship to the app as data over a CDN. The structure describes what to render. No executable code is downloaded.

**3. Render native** — The SDK converts specifications into real platform components. SwiftUI on iOS. Jetpack Compose on Android (coming). React on web. 60 FPS scrolling, native gestures, platform conventions. Not a web view.

All rendering logic lives in your app binary. Metabind delivers component specifications as data, the same way your app fetches JSON from any API.

## One Template. Dozens of Use Cases.

Spotlight isn't just for retail. Same components, different content.

| Use Case | Description |
|----------|-------------|
| Flash Sale | Promo code, product carousel, countdown timer, push-triggered entry |
| Product Launch | Hero video, feature highlights, countdown, pre-order CTA |
| Brand Editorial | Behind-the-scenes story with video, photography, pull quotes |
| Live Event | Real-time updating feed from a keynote, premiere, or product reveal |
| Market Alert | Financial updates, real-time data, actionable insights delivered natively |
| Patient Education | Care instructions with video demonstrations and interactive content |
| Course Content | Lessons and assessments that update as curriculum evolves |
| Seasonal Campaign | Holiday gift guides, themed promotions, limited-time experiences |

## FAQ

**Does this comply with App Store guidelines?**
Yes. All rendering logic is in your app binary, already reviewed and approved. Metabind delivers component specifications as data — the same way your app fetches JSON from any API. No executable code is downloaded at runtime. This is the same architecture the largest apps in the App Store use at scale.

**Is this just web views?**
No. Real SwiftUI on iOS. Real Jetpack Compose on Android. 60 FPS scrolling, native gestures, platform conventions. Clone the sample project and see for yourself.

**How long does integration take?**
The iOS SDK is a Swift Package. Add it, initialize the client, render a `MetabindView`. This sample project shows you exactly how. Most teams have a working integration in days.

**What about Android?**
The Jetpack Compose SDK is coming. The CMS and component definitions are platform-agnostic — content you create today renders on Android when the SDK ships. The web renderer is available now.

**Can I use this with my existing CMS?**
Yes. Metabind manages the native UI presentation layer. Your existing CMS manages content data. They complement each other — or use Metabind's built-in content management for both.

**What does this cost?**
The sample project is free. Metabind has a free tier for development and testing. See [metabind.ai](https://metabind.ai) for production plans.

## Project Structure

| File | Purpose |
|------|---------|
| `MetabindSampleSpotlightApp.swift` | App entry point — `MetabindClient` setup, environment injection, notification and deep-link wiring |
| `ContentView.swift` | All views — home screen with hero banner and info cards, push notification demo, CTA deep-link handling |
| `NotificationManager.swift` | Local notification scheduling and tap handling |
| `DeepLinkRouter.swift` | Parses `railpromotion://cta/<name>` URLs for CTA routing |

## Resources

- [Metabind Documentation](https://docs.metabind.ai)
- [iOS SDK Guide](https://docs.metabind.ai/guides/sdks/ios-sdk)
- [Metabind](https://metabind.ai)
- [metabind-apple SDK](https://github.com/metabindai/metabind-apple)
