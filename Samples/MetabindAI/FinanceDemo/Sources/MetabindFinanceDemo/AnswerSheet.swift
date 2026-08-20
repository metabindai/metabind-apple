import SwiftUI
import MetabindAI

/// One sheet for the whole thread.
///
/// The first answer looks like a plain detail sheet. Ask a follow-up and a
/// row of chips appears along the top — one per answer, behaving like tabs.
/// That keeps the whole chain reachable and legible without stacking sheets
/// ten deep or scrolling a transcript: the chips *are* the history, and
/// what's in them is what the model is working from.
///
/// Only the question is pinned. The answer's prose and its card scroll
/// under the header, passing through a fade rather than being cut off at an
/// edge.
struct AnswerSheet: View {
    @Bindable var router: AnswerRouter

    /// How far the header's background dissolves at its bottom edge.
    ///
    /// Drawn *inside* the header's height rather than added to it — it rides
    /// up over the title instead of pushing the content down. So the fade
    /// can be as long as it needs to be while the title and prose stay a
    /// tight 6pt apart.
    private let fadeHeight: CGFloat = 30

    /// Width of the fade between the chips and the close button. The chip
    /// row insets its content by the same amount, so scrolling to the end
    /// leaves the newest chip clear of the gradient rather than under it.
    private let chipFadeWidth: CGFloat = 26

    private var answer: AnswerRouter.Answer? {
        router.thread.indices.contains(router.selected) ? router.thread[router.selected] : router.thread.last
    }

    private var showsChips: Bool { router.thread.count > 1 }

    private var sheetBackground: Color { Color(.systemGroupedBackground) }

    var body: some View {
        ScrollView {
            if let answer {
                content(answer)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .scrollIndicators(.hidden)
        // An inset, so the card starts below the header but scrolls *under*
        // it — the header's background is what hides it, and the bottom of
        // that background is a gradient rather than an edge.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let answer { header(answer) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QuestionBar(
                prompts: .followUps,
                excluding: answer?.question,
                modelSuggestions: router.assistant.nextSteps,
                pending: router.pending?.question
            ) {
                router.ask($0)
            } onCancel: {
                router.cancelPending()
            }
        }
        .presentationDetents([.medium, .large], selection: detentBinding)
        .presentationDragIndicator(.visible)
        .presentationBackground(sheetBackground)
        .animation(.smooth(duration: 0.3), value: router.thread.count)
        .animation(.smooth(duration: 0.25), value: router.selected)
    }

    // MARK: - Header

    /// Two shapes, one anchor. With a single answer the question sits beside
    /// the close button; once chips appear they take that row and the
    /// question drops beneath. The close button doesn't move either way.
    private func header(_ answer: AnswerRouter.Answer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsChips {
                HStack(spacing: 10) {
                    ThreadChips(
                        answers: router.thread,
                        selected: router.selected,
                        trailingInset: chipFadeWidth,
                        onSelect: router.select
                    )
                    .mask(trailingFade)

                    closeButton
                        .padding(.trailing, 20)
                }

                title(answer)
                    .padding(.horizontal, 20)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    title(answer)
                    closeButton
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 32)
        .padding(.bottom, 6)
        .background(alignment: .top) { headerBackground }
    }

    private func title(_ answer: AnswerRouter.Answer) -> some View {
        Text(answer.question)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opaque behind the header, dissolving over its last `fadeHeight` so
    /// content doesn't disappear at a hard line.
    ///
    /// The stops hold near-opaque for the first half and do the real falloff
    /// late: the gradient overlaps the title, and a linear ramp would let
    /// scrolling content show faintly behind the text.
    private var headerBackground: some View {
        VStack(spacing: 0) {
            Rectangle().fill(sheetBackground)
            LinearGradient(
                stops: [
                    .init(color: sheetBackground, location: 0),
                    .init(color: sheetBackground.opacity(0.97), location: 0.4),
                    .init(color: sheetBackground.opacity(0.8), location: 0.62),
                    .init(color: sheetBackground.opacity(0.35), location: 0.84),
                    .init(color: sheetBackground.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
        }
        // Overshoot upward with padding rather than `ignoresSafeArea`: this
        // is the content of a `safeAreaInset`, and a view in there that both
        // reads and alters the safe area can feed its own layout.
        .padding(.top, -60)
        .allowsHitTesting(false)
    }

    /// Wrapped in a `GlassStack` on purpose. Interactive glass installs its
    /// own press gesture; bare — outside a `GlassEffectContainer` — that
    /// gesture isn't anchored and eats the button's tap, which is why this
    /// close button stopped registering while the identically-built rail
    /// pills (which do sit in a container) kept working. The explicit
    /// `contentShape` guarantees the whole 32pt circle is the hit target,
    /// not just the glyph.
    private var closeButton: some View {
        GlassStack {
            Button {
                router.dismissAnswer()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
                    .vaultGlass(in: .circle)
            }
            .vaultPressable()
        }
        .accessibilityLabel("Close")
    }

    /// Softens the chips out just before the close button, so a tab scrolling
    /// past doesn't collide with it.
    private var trailingFade: some View {
        HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: chipFadeWidth)
        }
    }

    // MARK: - Body

    private func content(_ answer: AnswerRouter.Answer) -> some View {
        // Wider than the title-to-prose gap on purpose: the pair above reads
        // as one block, and the card is the next thing down.
        VStack(alignment: .leading, spacing: 18) {
            if !answer.prose.isEmpty {
                BlurRevealText(markdown: answer.prose)
            }

            if !answer.sessions.isEmpty {
                AnswerCards(sessions: answer.sessions)
            } else if answer.prose.isEmpty {
                EmptyAnswerCard { router.retry(answer) }
            }
        }
        .id(answer.id)
        .transition(.opacity)
    }

    /// The router owns the detent so a component requesting fullscreen can
    /// push the sheet up without a view reaching back into it.
    private var detentBinding: Binding<PresentationDetent> {
        Binding(
            get: { router.detent == .large ? .large : .medium },
            set: { router.detent = $0 == .large ? .large : .medium }
        )
    }
}

/// The thread as tabs. Solid fills rather than glass — these sit on the
/// sheet's own surface, where glass-on-glass reads as mush, and a selected
/// tab needs to be unambiguous rather than subtle.
private struct ThreadChips: View {
    let answers: [AnswerRouter.Answer]
    let selected: Int
    /// Keeps the last chip out from under the trailing fade at scroll end.
    let trailingInset: CGFloat
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(answers.enumerated()), id: \.element.id) { index, answer in
                        Button {
                            onSelect(index)
                        } label: {
                            Text(PromptLabel.short(for: answer.question))
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(index == selected ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background {
                                    if index == selected {
                                        Capsule().fill(Vault.accent)
                                    } else {
                                        Capsule().fill(.fill.tertiary)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, trailingInset)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selected) { _, index in
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: answers.count) { _, count in
                // A new chip is always the newest, so run to the end rather
                // than centring it. Hopped a tick because scrolling to an id
                // inserted in this same update can land before it exists.
                Task { @MainActor in
                    withAnimation(.smooth(duration: 0.35)) {
                        proxy.scrollTo(count - 1, anchor: .trailing)
                    }
                }
            }
        }
    }
}

/// A result's description, revealed a word at a time with a soft blur-in — a
/// quick attention pull when the answer lands.
///
/// Height is reserved up front: every word is laid out at full size from the
/// first frame, and only blur and opacity animate, so the block never
/// reflows as it fills. Markdown is parsed once and sliced into word tokens
/// that each keep their own styling, so a bold run survives being split —
/// a plain space-split would turn `**$3,412**` into literal asterisks.
///
/// Resilient to streaming. The prose arrives in a tool response that updates
/// many times, so a one-shot reveal would only catch the first frame's
/// words. Each word owns its reveal: appended words are new `ForEach`
/// identities that mount and blur in on their own, already-shown words keep
/// their state, and a word that merely grows (`$3` → `$3,412`) keeps its
/// identity and updates in place without flashing.
///
/// The stagger is driven from here, not from each word's `onAppear`.
/// `onAppear` order across a freshly-mounted `ForEach` is unspecified — often
/// reverse — which read as the words revealing backwards. Instead a
/// controller walks a reveal cursor forward one index at a time on a timer,
/// so the ripple is always left to right; a streamed chunk simply raises the
/// target the cursor is heading toward.
struct BlurRevealText: View {
    let markdown: String
    var font: Font = .callout
    var color: Color = .primary

    /// One per block, reset on remount (a new answer or a refresh), so each
    /// answer starts its own ripple from zero.
    @State private var reveal = RevealController()

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    var body: some View {
        let attr = attributed
        let words = Self.tokenize(attr)

        FlowLayout(lineSpacing: 3) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                WordReveal(word: word, revealed: index < reveal.revealedCount)
            }
        }
        .font(font)
        .foregroundStyle(color)
        // The flow is a pile of separate word views; collapse it to one
        // element reading the full sentence for VoiceOver.
        .accessibilityElement()
        .accessibilityLabel(Text(String(attr.characters)))
        // `initial` reveals the first block; later changes raise the target
        // as more words stream in. Only fires on a count change, so a word
        // that merely grows in place never re-triggers it.
        .onChange(of: words.count, initial: true) { _, count in
            reveal.sync(to: count)
        }
    }

    /// Splits into bare word tokens, each with a single trailing space.
    ///
    /// The space is *normalized*, not copied from the source: runs of
    /// whitespace — including the `\n\n` paragraph breaks in the prose — all
    /// collapse to one space. Folding the original whitespace in instead
    /// would hand a token like `"flight.\n\n"` to the layout, which renders
    /// three lines tall and blows a giant gap into the flow. A word token
    /// must stay one line high.
    private static func tokenize(_ attr: AttributedString) -> [AttributedString] {
        let chars = attr.characters
        let space = AttributedString(" ")
        var tokens: [AttributedString] = []
        var i = attr.startIndex
        while i < attr.endIndex {
            while i < attr.endIndex, chars[i].isWhitespace { i = chars.index(after: i) }
            guard i < attr.endIndex else { break }
            let start = i
            while i < attr.endIndex, !chars[i].isWhitespace { i = chars.index(after: i) }
            var token = AttributedString(attr[start..<i])
            token.append(space)
            tokens.append(token)
        }
        return tokens
    }
}

/// One word of a ``BlurRevealText``. Stateless: whether it's blurred is told
/// to it by the controller, and the change animates because the controller
/// flips `revealedCount` inside a `withAnimation`.
private struct WordReveal: View {
    let word: AttributedString
    let revealed: Bool

    var body: some View {
        Text(word)
            .blur(radius: revealed ? 0 : 5)
            .opacity(revealed ? 1 : 0)
    }
}

/// Walks a reveal cursor forward, one word every `step`, up to a target that
/// grows as more prose streams in.
///
/// Revealing from here rather than per-word keeps the order deterministic —
/// index 0, then 1, then 2 — which `onAppear` couldn't promise. Each step is
/// wrapped in `withAnimation`, so the single word that crosses the cursor
/// blurs in while the rest hold. Raising the target mid-drain (a new chunk)
/// just extends the walk; a target reached and then raised again restarts it.
@Observable
@MainActor
final class RevealController {
    private(set) var revealedCount = 0
    private var target = 0
    private var drain: Task<Void, Never>?
    private let step: Duration = .milliseconds(30)

    func sync(to total: Int) {
        target = total
        if revealedCount > total { revealedCount = total }
        if drain == nil { start() }
    }

    private func start() {
        drain = Task { [weak self] in
            while let self, self.revealedCount < self.target {
                withAnimation(.smooth(duration: 0.3)) { self.revealedCount += 1 }
                try? await Task.sleep(for: self.step)
            }
            self?.drain = nil
        }
    }
}

/// A left-to-right wrapping layout — words flow onto the next line when they
/// run out of width, like text. Blur and opacity don't change a subview's
/// measured size, so the total height is settled on the first pass and holds
/// steady while `BlurRevealText` animates.
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        widest = max(widest, x - spacing)
        let width = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Answer Cards

/// The card — or cards — a turn produced.
///
/// A model can emit several tool calls in one message, which costs a single
/// inference pass rather than one per card. That makes "show me two things"
/// dramatically cheaper as a turn than as a conversation, so when it happens
/// the answer keeps all of them and offers a tab per card rather than showing
/// the first and discarding the rest.
///
/// With one card — the overwhelmingly common case — there is no tab bar and
/// this renders exactly as it did before.
struct AnswerCards: View {
    let sessions: [MCPAppSession]

    /// Which card is showing. Held here rather than on the router: it is view
    /// state, and it should reset when the answer changes, which `.id(answer)`
    /// on the caller already handles.
    @State private var selected = 0

    private var index: Int { min(selected, max(sessions.count - 1, 0)) }

    var body: some View {
        if sessions.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                tabs
                // Keyed by session so switching tabs swaps the card outright
                // instead of animating one into the other's frame.
                AnswerCard { MCPAppView(session: sessions[index]) }
                    .id(ObjectIdentifier(sessions[index]))
                    .transition(.opacity)
            }
            .animation(.smooth(duration: 0.22), value: index)
        } else if let session = sessions.first {
            AnswerCard { MCPAppView(session: session) }
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(sessions.enumerated()), id: \.offset) { offset, session in
                    Button {
                        selected = offset
                    } label: {
                        Text(Self.label(for: session))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(offset == index ? Color.primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if offset == index {
                                    // The card's own surface, so the selected
                                    // tab reads as the front edge of the card
                                    // beneath it rather than a separate chip.
                                    Capsule()
                                        .fill(Color(.secondarySystemGroupedBackground))
                                        .overlay(Capsule().strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
                                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                                } else {
                                    // A recess rather than a colour. `.primary`
                                    // inverts with the scheme, so this darkens
                                    // in light mode without going invisible
                                    // against a dark background.
                                    Capsule().fill(Color.primary.opacity(0.06))
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// A tab needs a name before its card has finished streaming, so this reads
    /// the tool name rather than anything inside the arguments. Falls back to
    /// prettifying the identifier, which keeps an unmapped tool legible instead
    /// of blank.
    static func label(for session: MCPAppSession) -> String {
        switch session.toolName {
        case "net_worth_trend":    return "Net worth"
        case "spending_breakdown": return "Spending"
        case "transaction_list":   return "Transactions"
        case "subscriptions":      return "Subscriptions"
        case "trend_card":         return "Trend"
        default:
            return session.toolName
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}
