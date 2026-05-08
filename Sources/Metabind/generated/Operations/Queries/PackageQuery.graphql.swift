// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class PackageQuery: GraphQLQuery {
  public static let operationName: String = "PackageQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query PackageQuery($version: String!) { package(version: $version) { __typename ...PackageFields } }"#,
      fragments: [AssetFields.self, ComponentFields.self, PackageDependencyFields.self, PackageFields.self, ResolvedPackageRefFields.self]
    ))

  public var version: String

  public init(version: String) {
    self.version = version
  }

  public var __variables: Variables? { ["version": version] }

  public struct Data: Metabind.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("package", Package?.self, arguments: ["version": .variable("version")]),
    ] }

    public var package: Package? { __data["package"] }

    /// Package
    ///
    /// Parent Type: `Package`
    public struct Package: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Package }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(PackageFields.self),
      ] }

      public var id: Metabind.ID { __data["id"] }
      public var version: String { __data["version"] }
      public var components: [Component] { __data["components"] }
      public var assets: [Asset] { __data["assets"] }
      public var dependencies: [Dependency] { __data["dependencies"] }
      public var compiled: String { __data["compiled"] }
      public var resolvedRef: ResolvedRef { __data["resolvedRef"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var packageFields: PackageFields { _toFragment() }
      }

      public typealias Component = PackageFields.Component

      public typealias Asset = PackageFields.Asset

      public typealias Dependency = PackageFields.Dependency

      public typealias ResolvedRef = PackageFields.ResolvedRef
    }
  }
}
