import Foundation
import Observation
import MCPAppsHost

/// Observable conversation state for a ``MetabindAssistant`` session.
///
/// Contains the ordered list of messages in a conversation. Access via
/// ``MetabindAssistant/conversation``. Mutations are performed internally
/// by the assistant during response generation.
@MainActor
@Observable
public final class Conversation {
    /// The messages in this conversation, in chronological order.
    public private(set) var messages: [Message] = []

    public init() {}

    // MARK: - Internal

    func append(_ message: Message) {
        messages.append(message)
    }

    func updateAssistantText(id: String, text: String) {
        if let index = messages.lastIndex(where: { $0.id == id }) {
            messages[index] = .assistant(id: id, text: text)
        }
    }

    func clear() {
        messages.removeAll()
    }
}
