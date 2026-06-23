import Testing
import Foundation
@testable import MCPAppsHost

@Suite("ContentResolver")
struct ResolverTests {

    // MARK: - BindJS Resolver

    @Test func bindJSResolverHandsJSON() {
        let resolver = BindJSResolver()
        #expect(resolver.canResolve(mimeType: "application/json"))
        #expect(resolver.canResolve(mimeType: "application/vnd.bindjs+json"))
        #expect(!resolver.canResolve(mimeType: "text/html"))
    }

    @Test func bindJSResolverProducesBindJS() async throws {
        let resolver = BindJSResolver()
        let resource = ResourceContent(
            uri: "ui://test/app",
            mimeType: "application/json",
            text: MockMCPServer.sampleBindJSResource
        )

        let result = try await resolver.resolve(resource)

        if case .bindJS(let content) = result {
            #expect(!content.compiled.isEmpty)
        } else {
            Issue.record("Expected .bindJS, got .html")
        }
    }

    @Test func bindJSResolverFailsOnNoText() async {
        let resolver = BindJSResolver()
        let resource = ResourceContent(uri: "ui://test/app", mimeType: "application/json")

        do {
            _ = try await resolver.resolve(resource)
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }

    @Test func bindJSResolverFailsOnInvalidJSON() async {
        let resolver = BindJSResolver()
        let resource = ResourceContent(
            uri: "ui://test/app",
            mimeType: "application/json",
            text: "not valid json {"
        )

        do {
            _ = try await resolver.resolve(resource)
            Issue.record("Expected error")
        } catch {
            // Expected — JSON decode failure
        }
    }

    @Test func bindJSResolverHandlesServerFormat() async throws {
        let resolver = BindJSResolver()
        let serverJSON = """
        {
          "layoutComponentName": "FeaturePageLayout",
          "packageVersion": "1.0.0",
          "package": {
            "version": "1.0.0",
            "compiled": {
              "components": {
                "FeaturePageLayout": "const body = (props) => { return Text('layout') }",
                "FeatureCard": "const body = (props) => { return Text('card') }"
              }
            }
          }
        }
        """
        let resource = ResourceContent(
            uri: "ui://metabind/render/test",
            mimeType: "application/vnd.bindjs+json",
            text: serverJSON
        )

        let result = try await resolver.resolve(resource)

        if case .bindJS(let content) = result {
            // compiled = layout component source
            #expect(content.compiled.contains("layout"))
            // components = other components (not the layout)
            #expect(content.package.components["FeatureCard"]?.contains("card") == true)
            #expect(content.package.components["FeaturePageLayout"] == nil)
            #expect(content.package.version == "1.0.0")
        } else {
            Issue.record("Expected .bindJS")
        }
    }

    // MARK: - HTML Resolver

    @Test func htmlResolverHandsHTML() {
        let resolver = HTMLResolver()
        #expect(resolver.canResolve(mimeType: "text/html"))
        #expect(resolver.canResolve(mimeType: "text/html;profile=mcp-app"))
        #expect(!resolver.canResolve(mimeType: "application/json"))
    }

    @Test func htmlResolverProducesHTML() async throws {
        let resolver = HTMLResolver()
        let resource = ResourceContent(
            uri: "ui://test/app",
            mimeType: "text/html",
            text: "<html><body>Hello</body></html>"
        )

        let result = try await resolver.resolve(resource)

        if case .html(let html) = result {
            #expect(html.contains("Hello"))
        } else {
            Issue.record("Expected .html")
        }
    }

    // MARK: - Package Cache

    @Test func packageCacheHitsOnSecondResolve() async throws {
        // Clear any prior cache state
        BindJSPackageCache.shared.store(
            layoutName: "_reset_",
            content: ResolvedContent(compiled: "", package: PackageComponents(version: "_none_", components: [:]))
        )

        let resolver = BindJSResolver()

        func makeResource(layout: String) -> ResourceContent {
            let json = """
            {
              "layoutComponentName": "\(layout)",
              "packageVersion": "2.0.0",
              "package": {
                "version": "2.0.0",
                "compiled": {
                  "components": {
                    "LayoutA": "const a = 1",
                    "LayoutB": "const b = 2",
                    "Shared": "const shared = true"
                  }
                }
              }
            }
            """
            return ResourceContent(uri: "ui://test/\(layout)", mimeType: "application/vnd.bindjs+json", text: json)
        }

        // First resolve: full decode
        let resultA = try await resolver.resolve(makeResource(layout: "LayoutA"))
        guard case .bindJS(let contentA) = resultA else {
            Issue.record("Expected .bindJS"); return
        }
        #expect(contentA.compiled == "const a = 1")
        #expect(contentA.package.components["LayoutB"] == "const b = 2")
        #expect(contentA.package.components["LayoutA"] == nil) // removed as layout

        // Second resolve with different layout: should hit cache
        let resultB = try await resolver.resolve(makeResource(layout: "LayoutB"))
        guard case .bindJS(let contentB) = resultB else {
            Issue.record("Expected .bindJS"); return
        }
        #expect(contentB.compiled == "const b = 2")
        #expect(contentB.package.components["LayoutA"] == "const a = 1")
        #expect(contentB.package.components["LayoutB"] == nil) // removed as layout
    }

    // MARK: - Default resolvers

    @Test func defaultResolversPreferBindJS() {
        let resolvers = defaultResolvers
        #expect(resolvers.count == 2)

        // BindJS resolver should be first (preferred)
        #expect(resolvers[0].canResolve(mimeType: "application/json"))
        #expect(resolvers[1].canResolve(mimeType: "text/html"))
    }
}
