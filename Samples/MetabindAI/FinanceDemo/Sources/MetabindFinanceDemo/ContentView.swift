import SwiftUI
import Security
import MetabindAI

struct ContentView: View {
    @State private var metabindApiKey: String = KeychainKey.initialValue()
    @State private var assistant: MetabindAssistant?

    /// Warm every card's `ui://` resource at connect time instead of fetching it
    /// the first time the model asks for that card.
    ///
    /// The SDK defaults this off, because it is only the right trade for a host
    /// that is going to render cards — which this one always does. Flip it and
    /// diff the two logs with `profile_log.py`; measured over five questions,
    /// on gave card resource waits of 80ms against 1632ms off, worst 39 against
    /// 514, and no cold `resources/read` landing mid-turn at all.
    ///
    /// It wins because connect is a whole inference ahead of the first card, so
    /// all five resources have landed before anything asks for one — and the
    /// 1.3MB does not slow the first turn's data calls (406/425ms with it on,
    /// 483/482ms off). Warming *later* than connect is the trap: fired just
    /// ahead of a card, those five reads queue in front of the one it needs and
    /// the card waited 1179ms — worse than never warming.
    static let prefetchUIResources = true

    private let orgId: String = Bundle.main.infoDictionary?["FinanceDemoOrgId"] as? String ?? "YOUR_ORG_ID"
    private let projectId: String = Bundle.main.infoDictionary?["FinanceDemoProjectId"] as? String ?? "YOUR_PROJECT_ID"
    private let agentHost = MetabindAgentProvider.productionHost
    private var mcpServerURL: URL {
        URL(string: "https://mcp.metabind.ai/\(orgId)/projects/\(projectId)")!
    }

    var body: some View {
        Group {
            if let assistant {
                // No chat, no navigation stack — the assistant's first answer
                // is the screen. See `HomeView`.
                HomeView(assistant: assistant, onResetAPIKey: resetAPIKey)
                    .id(ObjectIdentifier(assistant))
            } else {
                keyEntry
            }
        }
        .onAppear {
            if !metabindApiKey.isEmpty { start() }
        }
    }

    private var keyEntry: some View {
        VStack(spacing: 16) {
            Text("Enter your Metabind API key")
                .font(.headline)
            Text("Routed through the Metabind Agent proxy — no provider keys in the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("mb_\u{2026}", text: $metabindApiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
            Button("Start") { start() }
                .buttonStyle(.borderedProminent)
                .disabled(metabindApiKey.isEmpty)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Forgets the key and drops back to `keyEntry`. The reset is sticky, so a
    /// relaunch doesn't quietly reinstate the configured demo key.
    private func resetAPIKey() {
        KeychainKey.delete()
        assistant = nil
        metabindApiKey = ""
    }

    private func start() {
        KeychainKey.save(metabindApiKey)
        let provider = MetabindAgentProvider(
            baseURL: agentHost,
            apiKey: metabindApiKey,
            orgId: orgId,
            projectId: projectId
        )
        // A Metabind API key authenticates against both the agent proxy
        // and the MCP server — one key, two endpoints.
        assistant = MetabindAssistant(
            serverURL: mcpServerURL,
            serverHeaders: ["authorization": "Bearer \(metabindApiKey)"],
            provider: provider,
            configuration: .init(prefetchUIResources: Self.prefetchUIResources)
        )
    }
}

private enum KeychainKey {
    private static let fallbackBundleIdentifier = "com.example.MetabindFinanceDemo"
    private static let legacyPlaceholder = "YOUR_METABIND_API_KEY"

    static let service = "\(Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier)" + ".apiKey"
    static let account = "metabind-api-key"

    /// Optional configured key so private demo builds run without setup.
    static let configuredKey = Bundle.main.infoDictionary?["FinanceDemoAPIKey"] as? String ?? ""

    /// Set once "Reset API Key" runs, so the configured key stops seeding the field.
    /// Without it the reset would appear to work and then undo itself on the
    /// next launch.
    private static let wasResetDefault = "\(Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier)" + ".keyWasReset"

    /// Stored key if there is one, else the configured key — unless the user has
    /// explicitly reset, in which case they get an empty field.
    static func initialValue() -> String {
        if let stored = load(), stored != legacyPlaceholder { return stored }
        if UserDefaults.standard.bool(forKey: wasResetDefault) { return "" }
        return configuredKey
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func save(_ key: String) {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(attrs as CFDictionary)
        var add = attrs
        add[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
        UserDefaults.standard.set(false, forKey: wasResetDefault)
    }

    static func delete() {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(attrs as CFDictionary)
        UserDefaults.standard.set(true, forKey: wasResetDefault)
    }
}

#Preview {
    ContentView()
}
