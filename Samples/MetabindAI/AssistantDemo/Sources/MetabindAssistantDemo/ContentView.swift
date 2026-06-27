import SwiftUI
import Security
import MetabindAssistant

struct ContentView: View {
    @State private var metabindApiKey: String = KeychainKey.load() ?? ""
    @State private var assistant: MetabindAssistant?

    private let orgId = "IgJH0BzIn4LlfnCbcDc7"
    private let projectId = "Q0WNzrjYuO23n6k2EjKE"
    private let agentHost = MetabindAgentProvider.productionHost
    private let mcpServerURL = URL(string: "https://mcp.metabind.ai/IgJH0BzIn4LlfnCbcDc7/projects/Q0WNzrjYuO23n6k2EjKE")!

    var body: some View {
        NavigationStack {
            Group {
                if let assistant {
                    MetabindAssistantView(assistant: assistant)
                } else {
                    keyEntry
                }
            }
            .navigationTitle("Metabind Assistant")
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
            provider: provider
        )
    }
}

private enum KeychainKey {
    static let service = "com.example.MetabindAssistantDemo.apiKey"
    static let account = "metabind-api-key"

    static func load() -> String? {
        var query: [String: Any] = [
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
        _ = query
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
    }
}

#Preview {
    ContentView()
}
