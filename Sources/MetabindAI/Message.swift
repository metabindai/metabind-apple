import Foundation
import MCPAppsHost

/// A message in the assistant conversation.
///
/// Messages are displayed by ``MetabindAssistantView`` and are accessible
/// via ``MetabindAssistant/conversation``.
@MainActor
public enum Message: Identifiable {
    /// A message from the user.
    case user(id: String = UUID().uuidString, text: String)

    /// A text response from the assistant.
    case assistant(id: String = UUID().uuidString, text: String)

    /// A tool invocation with its rendering session.
    case tool(MCPAppSession)

    nonisolated public var id: String {
        switch self {
        case .user(let id, _): id
        case .assistant(let id, _): id
        case .tool(let session): session.id
        }
    }

    /// The text content of an assistant message, if any.
    /// Useful for observing streaming text updates in the UI.
    public var textContent: String? {
        switch self {
        case .assistant(_, let text): text
        default: nil
        }
    }
}
