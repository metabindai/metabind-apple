// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ContentTypesQuery: GraphQLQuery {
  public static let operationName: String = "ContentTypesQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ContentTypesQuery($search: String, $cursor: String, $limit: Int = 20) { contentTypes(search: $search, cursor: $cursor, limit: $limit) { __typename data { __typename ...ContentTypeFields } pagination { __typename cursor hasMore limit } } }"#,
      fragments: [ContentTypeFields.self]
    ))

  public var search: GraphQLNullable<String>
  public var cursor: GraphQLNullable<String>
  public var limit: GraphQLNullable<Int>

  public init(
    search: GraphQLNullable<String>,
    cursor: GraphQLNullable<String>,
    limit: GraphQLNullable<Int> = 20
  ) {
    self.search = search
    self.cursor = cursor
    self.limit = limit
  }

  public var __variables: Variables? { [
    "search": search,
    "cursor": cursor,
    "limit": limit
  ] }

  public struct Data: Metabind.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("contentTypes", ContentTypes.self, arguments: [
        "search": .variable("search"),
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }

    public var contentTypes: ContentTypes { __data["contentTypes"] }

    /// ContentTypes
    ///
    /// Parent Type: `ContentTypeList`
    public struct ContentTypes: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.ContentTypeList }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("data", [Datum].self),
        .field("pagination", Pagination.self),
      ] }

      public var data: [Datum] { __data["data"] }
      public var pagination: Pagination { __data["pagination"] }

      /// ContentTypes.Datum
      ///
      /// Parent Type: `ContentType`
      public struct Datum: Metabind.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.ContentType }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(ContentTypeFields.self),
        ] }

        public var id: Metabind.ID { __data["id"] }
        public var name: String { __data["name"] }
        public var packageVersion: String { __data["packageVersion"] }
        public var schema: String { __data["schema"] }
        public var updatedAt: Metabind.DateTime { __data["updatedAt"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var contentTypeFields: ContentTypeFields { _toFragment() }
        }
      }

      /// ContentTypes.Pagination
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
