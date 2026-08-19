import SwiftUI
import MetabindAI

/// The whole app, more or less. One question is asked on launch and its
/// rendered answer *is* the home screen; every later question is asked from
/// the rail at the bottom and answered in a sheet on top of it. There is no
/// transcript and no navigation stack pushing anywhere — you're always here.
struct HomeView: View {
    @State private var router: AnswerRouter
    @Environment(\.openURL) private var openURL

    private let assistant: MetabindAssistant

    /// Clears the stored key and returns to the entry screen. Owned by
    /// `ContentView` — it holds both the key and the assistant built from it.
    private let onResetAPIKey: () -> Void

    init(assistant: MetabindAssistant, onResetAPIKey: @escaping () -> Void) {
        self.assistant = assistant
        self.onResetAPIKey = onResetAPIKey
        _router = State(initialValue: AnswerRouter(assistant: assistant))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    question
                    answer
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) { wash }
            .background(Color(.systemGroupedBackground))
            // An inset rather than an overlay: the scroll view insets its own
            // content by the bar's height and the bar clears the home
            // indicator, instead of being cut off by it.
            .safeAreaInset(edge: .bottom, spacing: 0) { askBar }
            .navigationTitle("Metabind Finance")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    overflowMenu
                }
            }
        }
        .task(id: ObjectIdentifier(assistant)) {
            Self.wireHostBridge(assistant: assistant, router: router, openURL: openURL)
            router.onReset = { [weak assistant, weak router] in
                guard let assistant, let router else { return }
                Self.wireHostBridge(assistant: assistant, router: router, openURL: openURL)
            }
            router.start()
        }
        .onChange(of: assistant.conversation.messages.count) { _, _ in router.sync() }
        .onChange(of: assistant.isProcessing) { _, _ in router.sync() }
        // Ending the thread on dismiss rather than on tap, so the sheet
        // still has its content to animate away with.
        .sheet(isPresented: $router.isAnswerPresented, onDismiss: router.endThread) {
            AnswerSheet(router: router)
        }
        // Outside `.sheet` on purpose: components rendered in the sheet need
        // the bridge too, and a sheet only inherits environment applied
        // above the modifier that presents it.
        .environment(\.mcpHostBridge, assistant.hostBridge)
    }

    // MARK: - Overflow menu

    /// Refresh plus the demo's debug resets. Everything that acts on the whole
    /// screen rather than on one answer lives here.
    private var overflowMenu: some View {
        Menu {
            Button {
                router.reloadHome()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(router.isBusy)

            Section("Debug") {
                Button {
                    Task {
                        await assistant.clearResourceCaches()
                        router.reloadHome()
                    }
                } label: {
                    Label("Reset Cache", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(router.isBusy)

                Button(role: .destructive, action: onResetAPIKey) {
                    Label("Reset API Key", systemImage: "key.slash")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - Chrome

    /// A soft wash of the accent behind the top of the screen, so the home
    /// answer reads as the top of a page rather than a floating card.
    private var wash: some View {
        LinearGradient(
            colors: [Vault.accent.opacity(0.16), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 280)
        // Top only. It has no business reaching into the bottom inset, where
        // the ask bar and the keyboard are negotiating height.
        .ignoresSafeArea(edges: .top)
    }

    /// The question the screen is an answer to. The nav bar says what the app
    /// is; this says what you're looking at.
    private var question: some View {
        Text(AnswerRouter.homeQuestion)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var askBar: some View {
        QuestionBar(
            modelSuggestions: router.assistant.nextSteps,
            pending: router.pending?.question
        ) {
            router.ask($0)
        } onCancel: {
            router.cancelPending()
        }
    }

    // MARK: - The home answer

    @ViewBuilder
    private var answer: some View {
        if let home = router.home {
            VStack(alignment: .leading, spacing: 14) {
                if !home.prose.isEmpty {
                    // Keyed to the answer so a refresh re-runs the reveal;
                    // a stable id would leave it static after the first load.
                    BlurRevealText(markdown: home.prose)
                        .id(home.id)
                }

                if !home.sessions.isEmpty {
                    AnswerCards(sessions: home.sessions)
                } else if home.prose.isEmpty {
                    EmptyAnswerCard { router.retry(home) }
                }
            }
            .transition(.opacity)
        } else {
            LoadingCard()
        }
    }

    // MARK: - Wiring

    /// Handlers the assistant can't supply itself because they need SwiftUI
    /// environment. `MetabindAssistantView` does this for you; a custom UI
    /// has to do it by hand.
    private static func wireHostBridge(
        assistant: MetabindAssistant,
        router: AnswerRouter,
        openURL: OpenURLAction
    ) {
        let bridge = assistant.hostBridge
        bridge.handlers.onMessage = { [weak router] message in
            let text = message.content.compactMap { block -> String? in
                if case .text(let text) = block { return text }
                return nil
            }.joined(separator: "\n")
            router?.ask(text)
        }
        bridge.handlers.onOpenLink = { url in
            await withCheckedContinuation { continuation in
                openURL(url) { accepted in
                    continuation.resume(returning: accepted)
                }
            }
        }
        bridge.handlers.onDisplayMode = { [weak router] mode in
            MainActor.assumeIsolated {
                if mode == .fullscreen { router?.requestFullscreen() }
            }
            return mode
        }
    }
}

// MARK: - Cards

/// The frame every rendered MCP component sits in, so a component that
/// brings its own background and one that doesn't look like the same app.
struct AnswerCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}

/// Stand-in for the home answer while the first tool call is in flight. A
/// shaped placeholder beats a spinner here — the screen keeps its layout
/// instead of jumping when the card lands.
private struct LoadingCard: View {
    @State private var shimmer = false

    var body: some View {
        AnswerCard {
            VStack(alignment: .leading, spacing: 14) {
                bar(width: 0.5, height: 13)
                bar(width: 0.8, height: 13)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.fill.tertiary)
                    .frame(height: 180)
                bar(width: 0.65, height: 13)
            }
            .padding(18)
        }
        .opacity(shimmer ? 0.55 : 1)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.fill.tertiary)
                .frame(width: proxy.size.width * width)
        }
        .frame(height: height)
    }
}

/// A turn that came back with nothing to show — usually a dropped connection
/// or a question the tools can't answer.
struct EmptyAnswerCard: View {
    let onRetry: () -> Void

    var body: some View {
        AnswerCard {
            VStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Nothing came back for that one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try again", action: onRetry)
                    .buttonStyle(.bordered)
                    .tint(Vault.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 18)
        }
    }
}
