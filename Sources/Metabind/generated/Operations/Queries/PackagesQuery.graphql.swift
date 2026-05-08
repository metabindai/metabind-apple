// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class PackagesQuery: GraphQLQuery {
  public static let operationName: String = "PackagesQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query PackagesQuery($cursor: String, $limit: Int = 20) { packages(cursor: $cursor, limit: $limit) { __typename data { __typename ...PackageFields } pagination { __typename cursor hasMore limit } } }"#,
      fragments: [AssetFields.self, ComponentFields.self, PackageDependencyFields.self, PackageFields.self, ResolvedPackageRefFields.self]
    ))

  public var cursor: GraphQLNullable<String>
  public var limit: GraphQLNullable<Int>

  public init(
    cursor: GraphQLNullable<String>,
    limit: GraphQLNullable<Int> = 20
  ) {
    self.cursor = cursor
    self.limit = limit
  }

  public var __variables: Variables? { [
    "cursor": cursor,
    "limit": limit
  ] }

  public struct Data: Metabind.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("packages", Packages.self, arguments: [
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }

    public var packages: Packages { __data["packages"] }

    /// Packages
    ///
    /// Parent Type: `PackageList`
    public struct Packages: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.PackageList }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("data", [Datum].self),
        .field("pagination", Pagination.self),
      ] }

      public var data: [Datum] { __data["data"] }
      public var pagination: Pagination { __data["pagination"] }

      /// Packages.Datum
      ///
      /// Parent Type: `Package`
      public struct Datum: Metabind.SelectionSet {
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

      /// Packages.Pagination
      ///
      /// Parent Type: `CursorPagination`
      public struct Pagination: Metabind.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.CursorPagination }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("cursor", String?.self),
          .field("hasMore", Bool.self),
          .field("limit", Int.self),
        ] }

        public var cursor: String? { __data["cursor"] }
        public var hasMore: Bool { __data["hasMore"] }
        public var limit: Int { __data["limit"] }
      }
    }
  }
}
