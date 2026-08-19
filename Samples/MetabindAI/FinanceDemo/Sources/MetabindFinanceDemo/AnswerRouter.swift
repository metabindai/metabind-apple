import Foundation
import Observation
import MetabindAI

/// Turns a linear assistant conversation into a two-surface app.
///
/// The app never shows a transcript. Every turn lands in one of two places:
/// the *home* answer, which is the screen you launch into, and a *thread* —
/// a chain of answers presented in a sheet over the top.
///
/// The thread is the app's answer to context. Chat shows you everything the
/// model knows by piling it up forever; here the pile is scoped to one sheet
/// and thrown away when you close it, so what's in context is exactly what
/// you can see. Closing the sheet calls `reset()`, which clears the model's
/// memory server-side too — the chain really is gone, not just hidden.
@MainActor
@Observable
final class AnswerRouter {

    /// The question the home screen answers. Sent once, on launch — the home
    /// screen *is* its result, so changing this changes the whole app.
    static let homeQuestion = "Where did my money go this month?"

    /// One turn: the question asked, and what came back.
    struct Answer: Identifiable {
        let id = UUID()
        let question: String
        /// Where this turn begins in `conversation.messages`. Only valid
        /// until the next `reset()`, which is why `prose` is snapshotted
        /// rather than read from the conversation on demand.
        let startIndex: Int
        /// Every card this turn rendered, in the order the model asked for
        /// them. Usually one. A model may emit several tool calls in a single
        /// message, which costs one inference pass rather than one per card —
        /// so a turn that wants to show two things is far cheaper than two
        /// turns, and the app tabs them rather than dropping all but the first.
        var sessions: [MCPAppSession] = []
        /// The first card, which is the one presentation waits on.
        var session: MCPAppSession? { sessions.first }
        /// The assistant's prose for this turn. Updated while the turn
        /// streams, then left alone — so a thread's text survives the reset
        /// that ends it.
        var prose: String = ""
    }

    let assistant: MetabindAssistant

    /// The answer pinned to the home screen.
    private(set) var home: Answer?

    /// The chain currently in the sheet, oldest first. Surfaced as a row of
    /// chips once there's more than one, so the whole thread stays reachable
    /// from a single sheet.
    private(set) var thread: [Answer] = []

    /// Which answer in the thread the sheet is showing.
    private(set) var selected = 0

    /// The question in flight, if any — what the processing bubble shows.
    private(set) var pending: Answer?

    var isAnswerPresented = false
    var detent: SheetDetent = .medium

    /// True while the in-flight question is a home (re)load, which lands on
    /// the home screen instead of the thread.
    private var pendingIsHome = false

    /// Set when a question was asked while the assistant was still busy, so
    /// it can go out as soon as the current turn finishes.
    private var queued: String?

    /// Index of the last user message already accounted for, so a turn is
    /// never adopted twice. See ``adoptUntrackedTurn()``.
    private var handledUpTo = -1

    /// The delivered answer whose prose may still be streaming in.
    private var liveAnswerID: Answer.ID?

    /// Waits for the first rendered card to have trustworthy props.
    private var presentationTask: Task<Void, Never>?

    /// Called after a thread ends and the assistant is reset. The view uses
    /// it to re-attach host-bridge handlers to the assistant's new bridge.
    var onReset: (() -> Void)?

    enum SheetDetent { case medium, large }

    init(assistant: MetabindAssistant) {
        self.assistant = assistant
    }

    var isBusy: Bool { pending != nil || assistant.isProcessing }

    // MARK: - Asking

    /// Load the home answer. Safe to call repeatedly; only the first lands.
    func start() {
        guard home == nil, pending == nil else { return }
        reloadHome()
    }

    func reloadHome() {
        pendingIsHome = true
        send(Self.homeQuestion)
    }

    /// Ask a question. From the home rail this starts a thread; from inside
    /// the sheet it extends the one that's open.
    func ask(_ question: String) {
        // A question queued behind the home load must not change where the
        // in-flight home answer lands. `flushQueue()` calls back here once the
        // current turn finishes, at which point it becomes a thread answer.
        if !isBusy { pendingIsHome = false }
        // The chips let you jump back to an earlier answer, but the model's
        // history is linear — left alone it would read "that" as the most
        // recent turn, not the one on screen. Naming the focused answer
        // keeps the tabs meaning what they look like they mean.
        if let current = thread.indices.contains(selected) ? thread[selected] : nil,
           selected != thread.count - 1 {
            assistant.mergePendingContext(["focusedAnswer": current.question])
        }
        send(question)
    }

    func select(_ index: Int) {
        guard thread.indices.contains(index) else { return }
        selected = index
    }

    /// Re-run the question behind whichever surface the user is looking at.
    func retry(_ answer: Answer) {
        if answer.id == home?.id {
            reloadHome()
        } else {
            ask(answer.question)
        }
    }

    func cancelPending() {
        presentationTask?.cancel()
        presentationTask = nil
        assistant.cancel()
        assistant.clearPendingContext()
        // Mark it handled on the way out, or the next `sync()` would see an
        // unaccounted-for user message and adopt the turn straight back.
        if let pending { handledUpTo = pending.startIndex }
        pending = nil
        pendingIsHome = false
        queued = nil
    }

    private func send(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isBusy else {
            // Hold it rather than dropping it — `sync()` flushes the queue
            // when the current turn ends.
            queued = text
            return
        }
        // Captured before `send` so the index points at this turn's user
        // message, which is what `prose(from:)` slices from.
        pending = Answer(question: text, startIndex: assistant.conversation.messages.count)
        assistant.send(text)
    }

    // MARK: - Ending a thread

    /// Called once the sheet has finished dismissing. Ending the chain means
    /// ending it for the model too — otherwise the next question would
    /// silently inherit context the user can no longer see, which is the
    /// exact failure a visible thread is meant to avoid.
    func endThread() {
        guard !thread.isEmpty else { return }
        // A question still in flight has nowhere to land now, and letting it
        // finish would re-present the sheet over a thread that's gone.
        cancelPending()
        thread.removeAll()
        selected = 0
        liveAnswerID = nil
        handledUpTo = -1
        assistant.reset()
        // `reset()` drops the assistant's host bridge, so the handlers that
        // need SwiftUI environment have to go back on the new one or links
        // in the home card quietly stop opening.
        onReset?()
    }

    // MARK: - Routing

    /// Called whenever the conversation changes. Attaches the in-flight
    /// answer to its rendering session, keeps streaming prose up to date,
    /// and delivers turns that produce no card at all.
    func sync() {
        adoptUntrackedTurn()
        refreshProse()

        guard var pending else {
            flushQueue()
            return
        }

        // Text first. The model speaks once it has read the figures, which is a
        // whole tool call before it renders the card — so the sentence is sitting
        // in the conversation while the app is still waiting on the card to be
        // worth showing. Deliver the moment there is something to read and let
        // the card land underneath it: `refreshProse` keeps both the prose and
        // the session list current for the live answer afterwards.
        if !pending.prose.isEmpty {
            deliver(pending.id)
            return
        }

        let rendered = renderedSessions(from: pending.startIndex)
        if pending.sessions.isEmpty, let session = rendered.first {
            pending.sessions = rendered
            self.pending = pending
            let id = pending.id
            // A session is appended the moment the model *starts* the tool
            // call — arguments haven't even streamed in yet, so presenting
            // here slides the sheet up over an empty card. Waiting for the
            // *result* overcorrects: the SDK feeds every partial into the
            // card as it streams, and a composition card can take eight
            // seconds to type, all of it spent behind a closed sheet. Wait
            // for the first real props instead, and let the rest fill in
            // where the user can watch it.
            presentationTask?.cancel()
            presentationTask = Task { @MainActor [weak self] in
                let isPresentable = await Self.awaitPresentable(session) {
                    self != nil
                }
                guard isPresentable, let self else { return }
                self.deliver(id)
            }
            return
        }

        // A second card can land after the first was delivered — same message,
        // but its arguments stream in behind. Keep the in-flight answer's list
        // current so it isn't lost.
        if !pending.sessions.isEmpty, rendered.count != pending.sessions.count {
            pending.sessions = rendered
            self.pending = pending
        }

        // No card this turn: the prose is the whole answer, so it's ready as
        // soon as the assistant stops.
        if pending.session == nil, !assistant.isProcessing {
            deliver(pending.id)
        }
    }

    /// Resolves once the card has enough to be worth looking at — the resource
    /// resolved *and* at least one argument parsed out of the stream — or once
    /// the turn is over, whichever lands first.
    ///
    /// The floor matters: `phase` goes `.active` as soon as the BindJS package
    /// resolves, which happens before any argument has arrived, so `.active`
    /// alone still means an empty card. One parsed property is the earliest
    /// point the card draws something true.
    private static func awaitPresentable(
        _ session: MCPAppSession,
        while ownerExists: @MainActor () -> Bool
    ) async -> Bool {
        while ownerExists(), !Task.isCancelled {
            switch session.phase {
            case .completed, .failed, .cancelled:
                return true
            case .active:
                if let props = session.partialArguments?.objectValue, !props.isEmpty { return true }
            case .loading:
                break
            }
            // Polling rather than observation: props update many times a second
            // during a stream, and a 50ms floor keeps the sheet from animating
            // in on the very first fragment of a card that is about to fail.
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return false
    }

    /// Picks up a turn that started without going through ``ask(_:)``.
    ///
    /// A rendered component can talk back to the model — tapping a row in a
    /// transaction list calls `host.sendMessage`, which lands straight on
    /// the assistant. Without this, that turn would run with no bubble and
    /// its answer would never surface. Adopting it means a component-driven
    /// question extends the thread exactly like a tapped pill.
    private func adoptUntrackedTurn() {
        guard pending == nil else { return }
        let messages = assistant.conversation.messages
        guard let index = messages.lastIndex(where: { if case .user = $0 { true } else { false } }),
              index > handledUpTo,
              case .user(_, let text) = messages[index]
        else { return }

        pendingIsHome = false
        pending = Answer(question: text, startIndex: index)
    }

    private func deliver(_ id: Answer.ID) {
        guard var answer = pending, answer.id == id else { return }
        presentationTask?.cancel()
        presentationTask = nil
        pending = nil
        handledUpTo = answer.startIndex
        answer.prose = prose(from: answer.startIndex)
        liveAnswerID = answer.id

        if pendingIsHome {
            pendingIsHome = false
            home = answer
        } else {
            // Only reset the detent when the sheet is coming up fresh —
            // snapping back to medium mid-thread would undo a drag the user
            // just made.
            if !isAnswerPresented { detent = .medium }
            thread.append(answer)
            selected = thread.count - 1
            isAnswerPresented = true
        }
        flushQueue()
    }

    private func flushQueue() {
        guard let next = queued, !isBusy else { return }
        queued = nil
        ask(next)
    }

    func dismissAnswer() {
        isAnswerPresented = false
    }

    /// A component asked to take over the screen — give it the tall detent.
    func requestFullscreen() {
        detent = .large
    }

    // MARK: - Reading the conversation

    /// Keeps the in-flight answer and the one that just landed in step with
    /// the stream. Everything older is already snapshotted and never read
    /// from the conversation again, so a `reset()` can't hollow it out.
    private func refreshProse() {
        if var pending {
            pending.prose = prose(from: pending.startIndex)
            self.pending = pending
        }

        guard let liveAnswerID else { return }
        if var home, home.id == liveAnswerID {
            home.prose = prose(from: home.startIndex)
            home.sessions = renderedSessions(from: home.startIndex)
            self.home = home
        } else if let index = thread.firstIndex(where: { $0.id == liveAnswerID }) {
            thread[index].prose = prose(from: thread[index].startIndex)
            thread[index].sessions = renderedSessions(from: thread[index].startIndex)
        }
        if !assistant.isProcessing { self.liveAnswerID = nil }
    }

    /// Everything the assistant said between this turn's question and the
    /// next one.
    private func prose(from startIndex: Int) -> String {
        let messages = assistant.conversation.messages
        guard startIndex < messages.count else { return "" }

        var turn = Array(messages[startIndex...])
        if let next = turn.dropFirst().firstIndex(where: { if case .user = $0 { true } else { false } }) {
            turn = Array(turn[..<next])
        }
        // The first thing it says, not everything it says.
        //
        // A turn that reads the figures before rendering gives the model two
        // openings to talk: once when the numbers come back, once after the
        // card is drawn. It reliably takes both, and the second is the first
        // restated with the figures put back in — so joining them showed the
        // same observation twice, run together. Three attempts at instructing
        // it otherwise didn't hold; this is deterministic.
        //
        // First rather than last on the evidence: the remark it makes on
        // seeing the numbers is the analysis, and the one after the card is
        // the summary of what is already on screen.
        return turn
            .compactMap(\.textContent)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? ""
    }

    /// The first tool call in this turn that renders UI. Data-only tools feed
    /// the model but have nothing to show.
    private func renderedSessions(from index: Int) -> [MCPAppSession] {
        let messages = assistant.conversation.messages
        guard index < messages.count else { return [] }
        var found: [MCPAppSession] = []
        // `index` is this turn's own user message; a later one is the next
        // turn, and its cards are not ours.
        for (offset, message) in messages[index...].enumerated() {
            if offset > 0, case .user = message { break }
            if case .tool(let session) = message, session.resourceUri != nil {
                found.append(session)
            }
        }
        // One card per tool. A model that renders the same card twice in a turn
        // is correcting itself, not offering two views: it built a `trend_card`
        // from a `limit: 0` fetch, got no rows to plot, refetched and rendered
        // again. Both sessions are real, so both became tabs — two named
        // "Trend", the first empty. Genuine multi-card turns use *different*
        // tools, so keeping the last of each name drops the abandoned attempt
        // and keeps the pairing.
        var lastByTool: [String: MCPAppSession] = [:]
        for session in found { lastByTool[session.toolName] = session }
        return found.filter { lastByTool[$0.toolName] === $0 }
    }
}
