import SwiftUI
import MetabindContent

/// The app entry point. Demonstrates the two things every Metabind app needs:
///
/// 1. **Create a ``MetabindClient``** with your API credentials.
/// 2. **Inject it into the SwiftUI environment** with `.environment(client)` so that
///    ``MetabindView`` instances anywhere in the hierarchy can fetch and render content.
///
/// This sample also shows how to pair Metabind content with local push notifications
/// and deep-link routing — a common pattern for promotional campaigns.
@main
struct MetabindSampleSpotlightApp: App {

    // MARK: – Step 1: Create the client
    //
    // `MetabindClient` is an `@Observable` class, so we store it with `@State`
    // to give it a stable identity across view updates.
    //
    // To get your own credentials:
    //   1. Sign up free at metabind.ai/signup
    //   2. Create an org and project during onboarding
    //   3. Go to Settings (gear icon) → General → SDK section for your org/project IDs
    //   4. Go to Settings → API Keys → tap "+" to generate an API key (shown once — copy it)
    //
    // The url and ws endpoints are the same for all projects.

    @State var client = MetabindClient(
        url: URL(string: "https://api.metabind.ai/graphql")!,
        ws: URL(string: "wss://ws-api.metabind.ai")!,
        apiKey: <#API Key#>,
        organizationId: <#Organization ID#>,
        projectId: <#Project ID#>
    )

    @State private var notificationManager = NotificationManager()
    @State private var showPromotionSheet = false
    @State private var selectedCTA: String?

    var body: some Scene {
        WindowGroup {
            ContentView(
                selectedCTA: $selectedCTA,
                onShowNotification: {
                    Task {
                        await notificationManager.schedulePromotionNotification()
                    }
                }
            )
            // MARK: – Step 2: Inject into the environment
            //
            // Every `MetabindView` reads the client from the SwiftUI environment.
            // Place this modifier high in the view hierarchy so all descendants
            // can access it. Sheets and popovers create a new environment, so
            // remember to inject the client there too (see the `.sheet` below).
            .environment(client)
            .task {
                notificationManager.onNotificationTapped = {
                    showPromotionSheet = true
                }
            }
            .sheet(isPresented: $showPromotionSheet) {
                NotificationContentSheet(contentId: "cont_1772073374838679") { ctaName in
                    selectedCTA = ctaName
                    showPromotionSheet = false
                }
                // Sheets get their own environment — inject the client again.
                .environment(client)
            }
            .onOpenURL { url in
                if let route = DeepLinkRoute(url: url) {
                    switch route {
                    case .cta(let name):
                        selectedCTA = name
                        showPromotionSheet = false
                    }
                }
            }
        }
    }
}
