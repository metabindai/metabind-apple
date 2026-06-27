//
//  ContentView.swift
//  MetabindSampleSpotlight
//

import SwiftUI
import Metabind

struct ContentView : View {
    @Binding var selectedCTA: String?
    var onShowNotification: () -> Void

    var body : some View {
        NavigationStack {
            DemoView(selectedCTA: $selectedCTA, onShowNotification: onShowNotification)
                .navigationTitle("Demo")
        }
    }
}

struct DemoView : View {
    @Binding var selectedCTA: String?
    var onShowNotification: () -> Void

    var body : some View {
        List {
            Section {
                NavigationLink(destination: {
                    HomeView()
                }, label: {
                    Text("Home Screen")
                })

                NavigationLink(destination: {
                    PushNotificationDemoView(selectedCTA: $selectedCTA, onShowNotification: onShowNotification)
                }, label: {
                    Text("Push Notification")
                })

            }
        }
    }
}

// MARK: - Rendering CMS Content with MetabindView

/// Demonstrates the simplest way to display Metabind content: drop a
/// ``MetabindView`` into your layout and pass a content ID.
///
/// `MetabindView` handles fetching, caching, and rendering automatically.
/// You can mix it freely with native SwiftUI views — here it sits between a
/// native header and native product rails, showing how CMS-managed content
/// can coexist with hand-built UI.
///
/// Each content ID (e.g. `"cont_1772074912950486"`) maps to a piece of content
/// in Metabind. You can find these IDs in the inspector panel or
/// via the SDK's `fetchContent` API.
struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 48) {
                VStack {
                    WelcomeHeaderView()

                    // A promotional hero banner authored in Metabind.
                    // The layout, images, and copy are all managed in the CMS —
                    // updates publish instantly without an app release.
                    //
                    // `enableSubscription: true` opens a WebSocket subscription so
                    // the view updates in real time when content is published in the
                    // Metabind — no pull-to-refresh or app restart needed. Try editing
                    // this content in Metabind and watch it change on-device.
                    MetabindView(contentId: "cont_1772074912950486", enableSubscription: true)
                }

                // A second piece of content — an info-cards rail — also fully
                // CMS-driven. Multiple MetabindViews can appear on the same
                // screen, each fetching independently.
                MetabindView(contentId: "cont_1772070964812541")

                // Native views below — MetabindView is just another SwiftUI
                // view, so it composes naturally with the rest of your UI.
                NativeProductRail(title: "Shop Homewares")
                NativeProductRail(title: "Shop Bedding")
            }
        }
        .navigationTitle("Oak&Ivory")
    }
}

struct WelcomeHeaderView : View {
    var body : some View {
        VStack {
            Text("Welcome Back.")
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }
}

struct NativeProductRail : View {
    var title : String
    var body : some View {
        VStack {
            Container {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ProductCard()
                    ProductCard()
                    ProductCard()
                    ProductCard()
                }.padding(.horizontal)
            }
        }
    }
}

struct Container<Content: View> : View {
    var content : () -> Content
    var body : some View {
        content()
            .padding(.horizontal)
    }
}

struct ProductCard : View {
    var body : some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.1))
            .frame(width: 150, height: 150)
    }
}

// MARK: - Push Notification Demo

/// Shows how to trigger a local notification and display Metabind content
/// when the user taps it. This is a common pattern for promotional campaigns:
/// the notification payload contains a content ID, and the app presents a
/// ``MetabindView`` in a sheet to show the promotion.
struct PushNotificationDemoView: View {
    @Binding var selectedCTA: String?
    var onShowNotification: () -> Void
    @State private var isScheduling = false

    var body: some View {
        Group {
            if let cta = selectedCTA {
                ContentUnavailableView {
                    Label("CTA Selected", systemImage: "checkmark.circle.fill")
                } description: {
                    Text(cta)
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.tint.opacity(0.1), in: .capsule)

                    Text("The deep link was intercepted and routed back into the app.")
                } actions: {
                    Button("Try Again") {
                        selectedCTA = nil
                    }
                    .buttonStyle(.bordered)
                }
            } else if isScheduling {
                ContentUnavailableView {
                    ProgressView()
                        .controlSize(.large)
                } description: {
                    Text("Sending notification...\nIt should arrive in a moment.")
                }
            } else {
                ContentUnavailableView {
                    Label("Push Notification Demo", systemImage: "bell.badge")
                } description: {
                    Text("Tap the button to schedule a notification. When it arrives, tap it to view Metabind content.")
                } actions: {
                    Button("Show Notification") {
                        isScheduling = true
                        onShowNotification()
                        Task {
                            try? await Task.sleep(for: .seconds(4))
                            isScheduling = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .animation(.default, value: selectedCTA)
        .animation(.default, value: isScheduling)
        .navigationTitle("Push Notification")
    }
}

// MARK: - Handling Deep Links from MetabindView

/// Presents CMS content in a sheet and intercepts deep links from CTA buttons.
///
/// **Key technique:** Metabind content can contain buttons with custom URL
/// schemes (e.g. `railpromotion://cta/summer-sale`). Override SwiftUI's
/// `openURL` environment value to intercept these before the system handles
/// them. Return `.handled` to suppress the default behavior, or
/// `.systemAction` to let the OS open the URL normally.
///
/// This lets your marketing team wire up CTAs in Metabind while your app
/// routes them to the right screen — no app update required.
struct NotificationContentSheet: View {
    let contentId: String
    let onCTATapped: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MetabindView(contentId: contentId)
                // Intercept custom-scheme URLs from CTA buttons in the content.
                .environment(\.openURL, OpenURLAction { url in
                    if let route = DeepLinkRoute(url: url) {
                        switch route {
                        case .cta(let name):
                            onCTATapped(name)
                        }
                        return .handled
                    }
                    return .systemAction
                })
                .navigationTitle("Promotion")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

