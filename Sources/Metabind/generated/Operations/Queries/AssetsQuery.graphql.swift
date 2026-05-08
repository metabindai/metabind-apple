// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class AssetsQuery: GraphQLQuery {
  public static let operationName: String = "AssetsQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query AssetsQuery($type: String, $tags: [String!], $search: String, $filter: AssetFilter, $sort: [SortCriteria!], $cursor: String, $limit: Int = 20) { assets( type: $type tags: $tags search: $search filter: $filter sort: $sort cursor: $cursor limit: $limit ) { __typename data { __typename ...AssetFields } pagination { __typename cursor hasMore limit } } }"#,
      fragments: [AssetFields.self]
    ))

  public var type: GraphQLNullable<String>
  public var tags: GraphQLNullable<[String]>
  public var search: GraphQLNullable<String>
  public var filter: GraphQLNullable<AssetFilter>
  public var sort: GraphQLNullable<[SortCriteria]>
  public var cursor: GraphQLNullable<String>
  public var limit: GraphQLNullable<Int>

  public init(
    type: GraphQLNullable<String>,
    tags: GraphQLNullable<[String]>,
    search: GraphQLNullable<String>,
    filter: GraphQLNullable<AssetFilter>,
    sort: GraphQLNullable<[SortCriteria]>,
    cursor: GraphQLNullable<String>,
    limit: GraphQLNullable<Int> = 20
  ) {
    self.type = type
    self.tags = tags
    self.search = search
    self.filter = filter
    self.sort = sort
    self.cursor = cursor
    self.limit = limit
  }

  public var __variables: Variables? { [
    "type": type,
    "tags": tags,
    "search": search,
    "filter": filter,
    "sort": sort,
    "cursor": cursor,
    "limit": limit
  ] }

  public struct Data: Metabind.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("assets", Assets.self, arguments: [
        "type": .variable("type"),
        "tags": .variable("tags"),
        "search": .variable("search"),
        "filter": .variable("filter"),
        "sort": .variable("sort"),
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }

    public var assets: Assets { __data["assets"] }

    /// Assets
    ///
    /// Parent Type: `AssetList`
    public struct Assets: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.AssetList }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("data", [Datum].self),
        .field("pagination", Pagination.self),
      ] }

      public var data: [Datum] { __data["data"] }
      public var pagination: Pagination { __data["pagination"] }

      /// Assets.Datum
      ///
      /// Parent Type: `Asset`
      public struct Datum: Metabind.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Asset }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(AssetFields.self),
        ] }

        public var id: Metabind.ID { __data["id"] }
        public var name: String { __data["name"] }
        public var type: String { __data["type"] }
        public var url: String { __data["url"] }
        public var size: Int { __data["size"] }
        public var width: Int? { __data["width"] }
        public var height: Int? { __data["height"] }
        public var tags: [String] { __data["tags"] }
        public var updatedAt: Metabind.DateTime { __data["updatedAt"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var assetFields: AssetFields { _toFragment() }
        }
      }

      /// Assets.Pagination
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
