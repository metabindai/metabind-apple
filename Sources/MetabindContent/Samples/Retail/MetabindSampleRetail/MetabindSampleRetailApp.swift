//
//  MetabindSampleRetailApp.swift
//  MetabindSampleRetail
//
//  A minimal example demonstrating how to integrate Metabind into a SwiftUI app.
//

import Foundation
import SwiftUI
import MetabindContent

// MARK: - App Entry Point

/// The main entry point for the Metabind Sample Retail app.
///
/// This example demonstrates:
/// - Initializing a `MetabindClient` with your API credentials
/// - Injecting the client into the SwiftUI environment
/// - Displaying content using `MetabindView`
/// - Handling navigation actions between content pages
@main
struct MetabindSampleRetailApp: App {

    /// The Metabind client configured with your API credentials.
    ///
    /// Configure your credentials in the ignored `Config/Local.xcconfig`.
    /// Xcode substitutes them into the app's Info.plist when building.
    @State var client = MetabindClient(
        url: URL(string: "https://api.metabind.ai/graphql")!,
        ws: URL(string: "wss://ws-api.metabind.ai")!,
        apiKey: Bundle.main.object(forInfoDictionaryKey: "MetabindAPIKey") as? String ?? "",
        organizationId: Bundle.main.object(forInfoDictionaryKey: "MetabindOrgId") as? String ?? "",
        projectId: Bundle.main.object(forInfoDictionaryKey: "MetabindProjectId") as? String ?? ""
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(client)
    }
}

// MARK: - Content View

/// The main content view displaying Metabind content with navigation support.
///
/// This view demonstrates:
/// - Loading content by ID using `MetabindView`
/// - Enabling real-time subscriptions for live updates
/// - Handling `metabind.content` actions to navigate between pages
struct ContentView: View {

    /// Navigation path for managing the view stack.
    @State private var path = NavigationPath()

    /// The Metabind client from the environment.
    @Environment(MetabindClient.self) var client

    /// Navigation destinations for content pages.
    private enum Destination: Hashable {
        case content(id: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            // Display your root content page
            // Set your root content ID in Config/Local.xcconfig.
            ScrollView {
                MetabindView(
                    contentId: Bundle.main.object(forInfoDictionaryKey: "MetabindContentId") as? String ?? ""
                )
            }
                .onMetabindAction { action in
                    // Handle navigation to other content pages
                    if action.name == "metabind.content",
                       let contentId = action.props["contentId"] as? String
                    {
                        path.append(Destination.content(id: contentId))
                    }
                }
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .content(let id):
                        ScrollView {
                            MetabindView(contentId: id)
                        }
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
