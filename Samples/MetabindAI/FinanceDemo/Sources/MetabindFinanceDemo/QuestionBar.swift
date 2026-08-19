import SwiftUI

/// The one place you ask anything, pinned to the bottom of every surface —
/// home screen and answer sheet alike. Keeping it identical in both is what
/// lets a follow-up feel like it never left the screen it started on.
///
/// It has three states, and they're all the *same* piece of glass: the rail
/// of suggestions, the composer, and the in-flight question. Tapping a pill
/// morphs that pill into the processing bubble while the rest slide off the
/// bottom edge, so there's one object on screen the whole way through.
struct QuestionBar: View {
    /// Which set of prompts the rail offers. The home screen opens topics;
    /// a sheet continues one.
    var prompts: Prompts = .starters
    /// Hidden from the rail — usually the question you're already looking at.
    var excluding: String?
    /// Follow-ups the model attached to the card on screen. These lead the
    /// rail; `prompts` fills whatever room is left, so a turn that suggests
    /// nothing still offers something.
    var modelSuggestions: [String] = []
    /// The question in flight, if any. Non-nil puts the bar in its
    /// processing state.
    var pending: String?
    let onAsk: (String) -> Void
    let onCancel: () -> Void

    /// How far the scrim runs past the bottom of the bar, to cover the home
    /// indicator without touching the safe area.
    private let scrimOvershoot: CGFloat = 90

    @Namespace private var glass
    @State private var isComposing = false
    @State private var draft = ""
    /// Which element the big pill grows out of — the tapped suggestion, or
    /// the composer if the question was typed.
    @State private var morphID = Suggestion.askID
    /// The just-cleared question, kept briefly so the bubble outlives
    /// `pending` long enough for its border to fade. See `body`'s onChange.
    @State private var fadingQuestion: String?
    @FocusState private var fieldFocused: Bool

    enum Prompts {
        case starters, followUps

        /// Whether the model's follow-ups lead the rail or trail it.
        ///
        /// The sheet is mid-thread, so what the model suggests about the answer
        /// on screen beats a generic continuation. The home rail is the app's
        /// front door: its job is to offer the same openers every launch, so
        /// "How am I doing?" is always the first thing under your thumb. Let
        /// the model lead there and the front door reshuffles itself after
        /// every turn, which reads as randomness.
        var modelLeads: Bool { self == .followUps }
    }

    /// Most the rail will show. Enough to be worth scrolling, few enough that
    /// the model's suggestions aren't buried behind the fixed ones.
    private let railLimit = 5

    private var suggestions: [Suggestion] {
        let fixed = switch prompts {
        case .starters: Suggestion.starters
        case .followUps: Suggestion.followUps
        }
        let fromModel = modelSuggestions.map(Suggestion.fromModel)
        let ordered = prompts.modelLeads ? fromModel + fixed : fixed + fromModel

        // `Suggestion.id` is its text, so this drops both the question already
        // being answered and any fixed prompt the model happened to repeat.
        var seen = Set([excluding].compactMap { $0 })
        return ordered
            .filter { seen.insert($0.text).inserted }
            .prefix(railLimit)
            .map { $0 }
    }

    /// Only the pill the question came from gets a glass identity. Give the
    /// whole rail identities and the entire row smears into the bubble
    /// together; with one source, that pill alone stretches out of the rail
    /// while the others drop away with it.
    private func morphSource(_ id: String) -> String? {
        id == morphID ? id : nil
    }

    var body: some View {
        // Spacing is the distance at which two pieces of glass bond into
        // one. It has to stay under the gap between pills, or the rail
        // renders as a single blob instead of separate buttons.
        GlassStack(spacing: 6) {
            // `pending ?? fadingQuestion` keeps the bubble mounted for a beat
            // after the question clears, so its border can fade out in place.
            // Removing it the instant `pending` went nil would take the
            // border with it — no chance to fade — because a fade inside a
            // wholesale-removed subtree doesn't run.
            if let question = pending ?? fadingQuestion {
                bubble(question)
            } else if isComposing {
                composer
            } else {
                rail
            }
        }
        .animation(.smooth(duration: 0.45), value: pending)
        .animation(.smooth(duration: 0.45), value: fadingQuestion)
        .animation(.smooth(duration: 0.35), value: isComposing)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(alignment: .bottom) { scrim }
        // Mirror the live question into `fadingQuestion` *while* it's up, so
        // the instant `pending` clears the bubble doesn't blink out: onChange
        // runs after the render, so if we only set the fallback on clear,
        // there's one frame where `pending ?? fadingQuestion` is nil and the
        // bubble drops then snaps back — a flicker that read as a thick
        // border flash on dismiss.
        .onChange(of: pending, initial: true) { _, new in
            if let new {
                fadingQuestion = new
                return
            }
            // Cleared: `fadingQuestion` still holds it, so the bubble stays
            // mounted for the border's fade. Drop it after — unless another
            // question has taken its place by then.
            guard let held = fadingQuestion else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                if pending == nil, fadingQuestion == held { fadingQuestion = nil }
            }
        }
    }

    /// Lifts the bar off whatever is scrolling behind it. It runs past the
    /// bottom of the safe area so the fade finishes below the home indicator
    /// rather than stopping at a visible edge, and stays clear at the top so
    /// the glass still has something to refract.
    ///
    /// The overshoot is plain negative padding rather than
    /// `ignoresSafeArea`. This bar is the content of a `safeAreaInset`, so a
    /// view inside it that reads *and* alters the safe area can feed its own
    /// layout: the keyboard changes the inset, the inset re-lays out, the
    /// safe area changes again. Arithmetic can't loop.
    private var scrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: Color(.systemBackground).opacity(0), location: 0),
                    .init(color: Color(.systemBackground).opacity(0.7), location: 0.5),
                    .init(color: Color(.systemBackground), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Color(.systemBackground)
                .frame(height: scrimOvershoot)
        }
        .padding(.bottom, -scrimOvershoot)
        .allowsHitTesting(false)
    }

    // MARK: - Rail

    private var rail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                Pill(icon: "sparkles", text: "Ask anything", prominent: true) {
                    morphID = Suggestion.askID
                    isComposing = true
                    // Next tick: the field doesn't exist yet in this update,
                    // and focus aimed at a view that isn't there is dropped —
                    // which then reads as "focus lost" below.
                    Task { @MainActor in fieldFocused = true }
                }
                .vaultGlassID(morphSource(Suggestion.askID), in: glass)

                ForEach(suggestions) { suggestion in
                    Pill(icon: suggestion.icon, text: suggestion.short) {
                        morphID = suggestion.id
                        onAsk(suggestion.text)
                    }
                    .vaultGlassID(morphSource(suggestion.id), in: glass)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        // Lets the pills travel past the rail's bounds on their way out.
        .scrollClipDisabled()
        // On the rail rather than the pills: a transition inside a subtree
        // that's being removed wholesale doesn't get to run. The rail drops
        // off the bottom edge while the tapped pill's glass morphs into the
        // processing bubble.
        .transition(.offset(y: 96).combined(with: .opacity))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            // Deliberately not `axis: .vertical`. A field that grows with its
            // content changes the height of the `safeAreaInset` it lives in,
            // which moves the keyboard avoidance, which re-measures the
            // field — one ask box isn't worth that.
            TextField("Ask about your money", text: $draft)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .padding(.vertical, 12)

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Vault.accent, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.trailing, 6)
        }
        .vaultGlass()
        .vaultGlassID(Suggestion.askID, in: glass)
        .padding(.horizontal, 20)
        .onChange(of: fieldFocused) { _, focused in
            // Dismissing the keyboard on an untouched field puts the pills
            // back rather than stranding an empty text box.
            if !focused, draft.isEmpty, isComposing { isComposing = false }
        }
    }

    // MARK: - In flight

    /// Deliberately the biggest thing in the bar: full width, with room for
    /// two lines. While it's up it's the only thing on screen that's moving,
    /// and the size alone is enough to say so.
    private func bubble(_ question: String) -> some View {
        HStack(spacing: 14) {
            Text(question)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.fill.tertiary, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.vertical, 16)
        // A rounded rect rather than a capsule: at two lines a capsule's
        // ends bow out into lozenge shapes.
        .vaultGlass(in: .rect(cornerRadius: bubbleCorner, style: .continuous))
        // Back on the bubble's own glass rect — the geometry the border is
        // sized for. `active` drives its fade: on while a question is live,
        // off the moment `pending` clears, at which point the bubble lingers
        // (via `fadingQuestion`) just long enough for the fade to play.
        .overlay {
            AISweepBorder(cornerRadius: bubbleCorner, active: pending != nil)
        }
        .vaultGlassID(morphID, in: glass)
        .padding(.horizontal, 20)
    }

    private let bubbleCorner: CGFloat = 26

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        fieldFocused = false
        isComposing = false
        morphID = Suggestion.askID
        onAsk(text)
    }
}

private struct Pill: View {
    let icon: String
    let text: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(prominent ? Vault.accent : .secondary)
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .vaultGlass(tint: prominent ? Vault.accent.opacity(0.18) : nil)
        }
        .vaultPressable()
    }
}

// MARK: - Liquid glass

/// Wraps content in a `GlassEffectContainer` where the OS has one, so
/// sibling glass elements can merge and morph into each other.
struct GlassStack<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Liquid glass where it exists, a material capsule where it doesn't.
    @ViewBuilder
    func vaultGlass(in shape: some Shape = Capsule(), tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.separator.opacity(0.5), lineWidth: 0.5))
        }
    }

    /// Marks this view as one identity within a ``GlassStack``. Two states
    /// sharing an id morph into one another instead of cross-fading; pass
    /// nil to opt a view out of morphing entirely.
    @ViewBuilder
    func vaultGlassID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Interactive glass supplies its own press feedback; older systems need
    /// the scale put back by hand.
    @ViewBuilder
    func vaultPressable() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.plain)
        } else {
            buttonStyle(PressableButtonStyle())
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Suggestions

private struct Suggestion: Identifiable {
    let icon: String
    /// What fits on a pill.
    let short: String
    /// What the assistant is actually asked.
    let text: String

    var id: String { text }

    /// Identity of the "Ask anything" pill, which the composer grows out of.
    static let askID = "ask-anything"

    /// Icons the model may put on a follow-up, keyed by the name it writes.
    ///
    /// A closed vocabulary rather than "any SF Symbol": `Image(systemName:)`
    /// draws nothing for a name that doesn't exist, so an invented one would
    /// leave a pill with a hole in it. The same ten names are listed in the
    /// server instructions — that list and this one have to agree, and this
    /// side is the one that fails safe.
    static let modelIcons: Set<String> = [
        "calendar",                        // a different time period
        "chart.line.uptrend.xyaxis",       // a trend
        "chart.pie.fill",                  // a breakdown
        "arrow.up.arrow.down",             // a comparison
        "magnifyingglass",                 // more detail
        "creditcard.fill",                 // transactions
        "banknote.fill",                   // income
        "repeat",                          // recurring charges
        "exclamationmark.triangle.fill",   // something unusual
        "lightbulb.fill",                  // advice
    ]

    /// Stands in when the model omits the prefix or names an icon we don't
    /// carry. Reads as "next" rather than as a wrong topic.
    static let fallbackIcon = "arrow.forward"

    /// A follow-up the model wrote for the card on screen, in the form
    /// `icon|question` — e.g. `calendar|Show me last month`.
    ///
    /// Forgiving on purpose. A missing prefix, an unknown icon or a stray pipe
    /// costs the pill its icon, never the pill: the question is the part the
    /// user needs, and it's already phrased the way they'd say it.
    ///
    /// A factory rather than an `init`, so the memberwise initializer the
    /// fixed lists below rely on survives.
    static func fromModel(_ raw: String) -> Suggestion {
        guard let pipe = raw.firstIndex(of: "|") else {
            return Suggestion(icon: fallbackIcon, short: raw, text: raw)
        }

        let name = raw[..<pipe].trimmingCharacters(in: .whitespaces)
        let question = raw[raw.index(after: pipe)...].trimmingCharacters(in: .whitespaces)

        // Does the left side look like a symbol name at all? Icon names are one
        // unspaced token; a pipe inside a real question ("Is it A|B?") has
        // words either side. Without this test an off-list name like
        // `chart.bar.fill` would be shown to the user as pill text.
        let looksLikeIconName = !name.isEmpty && !name.contains(" ") && name.count < 40

        guard !question.isEmpty, looksLikeIconName else {
            return Suggestion(icon: fallbackIcon, short: raw, text: raw)
        }
        // Recognised name draws its icon; anything else still loses the prefix,
        // so a hallucinated symbol costs the icon rather than the wording.
        let icon = modelIcons.contains(name) ? name : fallbackIcon
        return Suggestion(icon: icon, short: question, text: question)
    }

    /// Openers, shown on the home screen. One per tool pairing, so every
    /// pill exercises a different renderer.
    static let starters: [Suggestion] = [
        Suggestion(icon: "chart.line.uptrend.xyaxis", short: "How am I doing?", text: "How am I doing?"),
//        Suggestion(icon: "cart.fill", short: "Groceries", text: "What did I spend on groceries last month?"),
//        Suggestion(icon: "repeat", short: "Subscriptions", text: "What subscriptions am I paying for?"),
//        Suggestion(icon: "fork.knife", short: "Dining", text: "What did I spend on dining?"),
//        Suggestion(icon: "exclamationmark.triangle.fill", short: "Anything unusual?", text: "Were there any unusual charges this month?"),
    ]

    /// Continuations, shown in a sheet. Every one leans on "that" — they only
    /// make sense against the answer above them, which is the whole point:
    /// the chips are what makes the thread's context usable without showing
    /// the user a transcript to reason about.
    ///
    /// These are fixed for now. The natural next step is for the answer to
    /// carry its own — either a `suggest_next_steps`-style MCP tool, or
    /// follow-ups keyed off `session.toolName` — at which point this list
    /// becomes the fallback rather than the whole story.
    static let followUps: [Suggestion] = [
        Suggestion(icon: "calendar", short: "Compare months", text: "How does that compare over the last 6 months ?"),
//        Suggestion(icon: "list.bullet", short: "Show transactions", text: "Show me the individual transactions behind that."),
//        Suggestion(icon: "questionmark.circle", short: "Why the change?", text: "Why did that change?"),
//        Suggestion(icon: "arrow.up.right", short: "Biggest movers", text: "What were the biggest movers in that?"),
//        Suggestion(icon: "target", short: "Set a budget", text: "Should I set a budget for that?"),
    ]
}

/// Shortens a question to something that fits on a chip.
enum PromptLabel {
    /// The suggestion's own short form when the question came from one,
    /// otherwise a trimmed version of whatever was typed.
    static func short(for question: String) -> String {
        let all = Suggestion.starters + Suggestion.followUps
        if let match = all.first(where: { $0.text == question }) {
            return match.short
        }

        let trimmed = question
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?."))
        guard trimmed.count > 22 else { return trimmed }

        // Cut on a word boundary so the ellipsis doesn't land mid-word.
        let clipped = trimmed.prefix(22)
        let end = clipped.lastIndex(of: " ").map(clipped.index(after:)) ?? clipped.endIndex
        return clipped[..<end].trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}

/// The app's one bit of brand. Everything else leans on system materials so
/// the rendered MCP components stay the loudest thing on screen.
enum Vault {
    static let accent = Color(red: 0.13, green: 0.55, blue: 0.42)
}

/// A bright arc that sweeps continuously around a rounded-rect edge — the
/// app's "AI is working" signal, standing in for a spinner.
///
/// The rotation is driven by `TimelineView(.animation)` — recomputing the
/// gradient's angle from the frame clock — rather than animating a `@State`
/// angle. SwiftUI won't interpolate a gradient's `angle` parameter through an
/// implicit animation, so a state-driven version jumps; reading the clock
/// each frame gives a genuinely smooth turn.
///
/// `active` gates its own opacity, asymmetrically: on it holds back past the
/// glass morph then fades in (the overlay can't ride the morph, so drawn
/// immediately it would snap to full size while the glass is still growing);
/// off it fades away fast, so it's gone almost as the bubble starts morphing
/// back rather than popping.
struct AISweepBorder: View {
    let cornerRadius: CGFloat
    var active: Bool
    var lineWidth: CGFloat = 4.6
    /// Seconds per full lap.
    var period: Double = 2.2
    /// Held back this long before fading in, to clear the glass morph.
    var appearDelay: Double = 0.4

    @State private var appeared = false

    /// Lit only once mounted *and* active — so a fresh mount fades in rather
    /// than snapping on.
    private var visible: Bool { appeared && active }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let turn = t.truncatingRemainder(dividingBy: period) / period
            let sweep = AngularGradient(
                // Locations must climb monotonically 0→1, or SwiftUI rejects
                // the gradient every frame ("stop locations must be
                // ordered"). Closing on the same colour it opens with keeps
                // the wrap seamless as it spins.
                stops: [
                    .init(color: .blue, location: 0.00),
                    .init(color: Vault.accent.opacity(0.9), location: 0.26),
                    .init(color: .white, location: 0.38),
                    .init(color: Vault.accent.opacity(0.9), location: 0.50),
                    .init(color: .white, location: 0.74),
                    .init(color: Vault.accent.opacity(0.9), location: 0.88),
                    .init(color: .blue, location: 1.00),
                ],
                center: .center,
                angle: .degrees(turn * 360)
            )

            ZStack {
                // A faint full ring so the edge reads as lit all the way
                // round, not just where the bright arc happens to be.
                shape.strokeBorder(Vault.accent.opacity(0.18), lineWidth: lineWidth)
                // The moving arc, plus a blurred copy under it for glow.
                shape.strokeBorder(sweep, lineWidth: lineWidth)
                    .blur(radius: 6)
                shape.strokeBorder(sweep, lineWidth: lineWidth)
            }
        }
        // Border only — never steal the cancel button's taps.
        .allowsHitTesting(false)
        .opacity(visible ? 1 : 0)
        // Scoped to `visible`, and picking its curve from the destination:
        // delayed ease-out in (clear the glass morph), quick ease-in out.
        // Keying the animation to this value rather than wrapping the change
        // in `withAnimation` keeps the bar's ambient 0.45s animation from
        // catching the opacity and rebounding it to full on dismiss.
        .animation(
            // Both ease-out: fading in, a soft arrival; fading out, alpha
            // drops fast at the start so it reads as an immediate vanish
            // rather than holding full then snapping (which ease-in does).
            visible ? .easeOut(duration: 0.3).delay(appearDelay) : .easeOut(duration: 0.15),
            value: visible
        )
        .onAppear { appeared = true }
    }
}

#Preview {
    VStack {
        Spacer()
        QuestionBar(pending: nil) { _ in } onCancel: {}
    }
}
