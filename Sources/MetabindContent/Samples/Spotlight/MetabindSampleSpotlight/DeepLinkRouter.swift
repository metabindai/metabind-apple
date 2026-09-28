import Foundation

/// Parses custom-scheme deep links emitted by CTA buttons in Metabind content.
///
/// In Metabind, authors can set a button's action URL to a custom
/// scheme like `railpromotion://cta/summer-sale`. When the user taps that
/// button inside a ``MetabindView``, SwiftUI's `openURL` fires. We intercept
/// it (see ``NotificationContentSheet``) and parse the URL here to determine
/// which screen or action to route to.
///
/// URL format: `railpromotion://cta/<name>`
enum DeepLinkRoute {
    case cta(name: String)

    init?(url: URL) {
        guard url.scheme == "railpromotion",
              url.host() == "cta" else {
            return nil
        }
        let name = url.pathComponents.dropFirst().first ?? "unknown"
        self = .cta(name: name)
    }
}
