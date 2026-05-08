// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ExecuteSavedSearchQuery: GraphQLQuery {
  public static let operationName: String = "ExecuteSavedSearchQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ExecuteSavedSearchQuery($id: ID!, $cursor: String, $limit: Int = 20) { executeSavedSearch(id: $id, cursor: $cursor, limit: $limit) { __typename ... on ContentList { __typename data { __typename ...ContentFields } pagination { __typename cursor hasMore limit } } ... on AssetList { __typename data { __typename ...AssetFields } pagination { __typename cursor hasMore limit } } } }"#,
      fragments: [AssetFields.self, ContentFields.self, ResolvedPackageRefFields.self]
    ))

  public var id: ID
  public var cursor: GraphQLNullable<String>
  public var limit: GraphQLNullable<Int>

  public init(
    id: ID,
    cursor: GraphQLNullable<String>,
    limit: GraphQLNullable<Int> = 20
  ) {
    self.id = id
    self.cursor = cursor
    self.limit = limit
  }

  public var __variables: Variables? { [
    "id": id,
    "cursor": cursor,
    "limit": limit
  ] }

  public struct Data: Metabind.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("executeSavedSearch", ExecuteSavedSearch.self, arguments: [
        "id": .variable("id"),
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }

    public var executeSavedSearch: ExecuteSavedSearch { __data["executeSavedSearch"] }

    /// ExecuteSavedSearch
    ///
    /// Parent Type: `SavedSearchResult`
    public struct ExecuteSavedSearch: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Unions.SavedSearchResult }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .inlineFragment(AsContentList.self),
        .inlineFragment(AsAssetList.self),
      ] }

      public var asContentList: AsContentList? { _asInlineFragment() }
      public var asAssetList: AsAssetList? { _asInlineFragment() }

      /// ExecuteSavedSearch.AsContentList
      ///
      /// Parent Type: `ContentList`
      public struct AsContentList: Metabind.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ExecuteSavedSearchQuery.Data.ExecuteSavedSearch
        public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.ContentList }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("data", [Datum].self),
          .field("pagination", Pagination.self),
        ] }

        public var data: [Datum] { __data["data"] }
        public var pagination: Pagination { __data["pagination"] }

        /// ExecuteSavedSearch.AsContentList.Datum
        ///
        /// Parent Type: `Content`
        public struct Datum: Metabind.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Content }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(ContentFields.self),
          ] }

          public var id: Metabind.ID { __data["id"] }
          public var typeId: Metabind.ID { __data["typeId"] }
          public var packageVersion: String { __data["packageVersion"] }
          public var name: String { __data["name"] }
          public var content: String { __data["content"] }
          public var compiled: String { __data["compiled"] }
          public var tags: [String] { __data["tags"] }
          public var locale: String? { __data["locale"] }
          public var createdAt: Metabind.DateTime { __data["createdAt"] }
          public var updatedAt: Metabind.DateTime { __data["updatedAt"] }
          public var lastPublishedVersion: Int? { __data["lastPublishedVersion"] }
          public var resolvedRef: ResolvedRef { __data["resolvedRef"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var contentFields: ContentFields { _toFragment() }
          }

          public typealias ResolvedRef = ContentFields.ResolvedRef
        }

        /// ExecuteSavedSearch.AsContentList.Pagination
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

      /// ExecuteSavedSearch.AsAssetList
      ///
      /// Parent Type: `AssetList`
      public struct AsAssetList: Metabind.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ExecuteSavedSearchQuery.Data.ExecuteSavedSearch
        public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.AssetList }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("data", [Datum].self),
          .field("pagination", Pagination.self),
        ] }

        public var data: [Datum] { __data["data"] }
        public var pagination: Pagination { __data["pagination"] }

        /// ExecuteSavedSearch.AsAssetList.Datum
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

        /// ExecuteSavedSearch.AsAssetList.Pagination
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
}
