import SwiftUI
import MCPAppsHost

/// A drop-in conversational AI view powered by ``MetabindAssistant``.
///
/// Renders the full conversation UI: message bubbles, tool result rendering
/// via `MCPAppView`, a text input field, and streaming indicators.
///
/// For custom UI, read ``MetabindAssistant/conversation`` directly and build
/// your own views around the ``Message`` array.
///
/// ```swift
/// struct ContentView: View {
///     let assistant: MetabindAssistant
///
///     var body: some View {
///         MetabindAssistantView(assistant: assistant)
///     }
/// }
/// ```
public struct MetabindAssistantView: View {
    private let assistant: MetabindAssistant
    @State private var inputText = ""
    @Environment(\.openURL) private var openURL

    public init(assistant: MetabindAssistant) {
        self.assistant = assistant
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .background(.background)
        .task(id: ObjectIdentifier(assistant)) {
            wireHostBridgeUIHandlers()
        }
        .environment(\.mcpHostBridge, assistant.hostBridge)
    }

    /// Fills in the bridge handlers that depend on SwiftUI environment —
    /// the assistant itself can't reach `@Environment(\.openURL)`. Kept
    /// here so the assistant's bridge picks up host-view capabilities
    /// whenever the view mounts.
    private func wireHostBridgeUIHandlers() {
        let bridge = assistant.hostBridge
        let openURL = openURL
        bridge.handlers.onOpenLink = { url in
            await withCheckedContinuation { continuation in
                openURL(url) { accepted in
                    continuation.resume(returning: accepted)
                }
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(assistant.conversation.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if assistant.isProcessing {
                        streamingIndicator
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: assistant.conversation.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if assistant.isProcessing {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let last = assistant.conversation.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var streamingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking\u{2026}")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .id("streaming")
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: .rect(cornerRadius: 20))
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || assistant.isProcessing
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func send() {
        let text = inputText
        inputText = ""
        assistant.send(text)
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        switch message {
        case .user(_, let text):
            HStack {
                Spacer()
                Text(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.tint, in: .rect(cornerRadius: 18))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)

        case .assistant(_, let text):
            HStack {
                Text(.init(text))
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(.horizontal)

        case .tool(let session):
            // Hide data-only tool bubbles from the default chat UI — they
            // feed the model but shouldn't surface raw JSON to the user.
            // Custom UIs can still read `assistant.conversation.messages`
            // and render them however they like.
            let failed: Bool = if case .failed = session.phase { true } else { false }
            if session.resourceUri != nil || failed {
                MCPAppView(session: session) { content in
                    content
                        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
                } placeholder: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(session.toolName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
            }
        }
    }
}
