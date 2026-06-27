// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class TagsQuery: GraphQLQuery {
  public static let operationName: String = "TagsQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query TagsQuery($search: String, $cursor: String, $limit: Int = 20) { tags(search: $search, cursor: $cursor, limit: $limit) { __typename data { __typename ...TagFields } pagination { __typename cursor hasMore limit } } }"#,
      fragments: [TagFields.self]
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

  public struct Data: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("tags", Tags.self, arguments: [
        "search": .variable("search"),
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }

    public var tags: Tags { __data["tags"] }

    /// Tags
    ///
    /// Parent Type: `TagList`
    public struct Tags: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.TagList }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("data", [Datum].self),
        .field("pagination", Pagination.self),
      ] }

      public var data: [Datum] { __data["data"] }
      public var pagination: Pagination { __data["pagination"] }

      /// Tags.Datum
      ///
      /// Parent Type: `Tag`
      public struct Datum: MetabindContent.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Tag }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(TagFields.self),
        ] }

        public var id: MetabindContent.ID { __data["id"] }
        public var name: String { __data["name"] }
        public var slug: String { __data["slug"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var tagFields: TagFields { _toFragment() }
        }
      }

      /// Tags.Pagination
      ///
      /// Parent Type: `CursorPagination`
      public struct Pagination: MetabindContent.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.CursorPagination }
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
