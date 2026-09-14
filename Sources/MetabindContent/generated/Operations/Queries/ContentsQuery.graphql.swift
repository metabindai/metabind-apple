// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ContentsQuery: GraphQLQuery {
  public static let operationName: String = "ContentsQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ContentsQuery($typeId: ID, $tags: [String!], $locale: String, $search: String, $filter: ContentFilter, $sort: [SortCriteria!], $cursor: String, $limit: Int = 20) { contents( typeId: $typeId tags: $tags locale: $locale search: $search filter: $filter sort: $sort cursor: $cursor limit: $limit ) { __typename data { __typename ...ContentFields } pagination { __typename cursor hasMore limit } } }"#,
      fragments: [ContentFields.self, ResolvedPackageRefFields.self]
    ))

  public var typeId: GraphQLNullable<ID>
  public var tags: GraphQLNullable<[String]>
  public var locale: GraphQLNullable<String>
  public var search: GraphQLNullable<String>
  public var filter: GraphQLNullable<ContentFilter>
  public var sort: GraphQLNullable<[SortCriteria]>
  public var cursor: GraphQLNullable<String>
  public var limit: GraphQLNullable<Int>

  public init(
    typeId: GraphQLNullable<ID>,
    tags: GraphQLNullable<[String]>,
    locale: GraphQLNullable<String>,
    search: GraphQLNullable<String>,
    filter: GraphQLNullable<ContentFilter>,
    sort: GraphQLNullable<[SortCriteria]>,
    cursor: GraphQLNullable<String>,
    limit: GraphQLNullable<Int> = 20
  ) {
    self.typeId = typeId
    self.tags = tags
    self.locale = locale
    self.search = search
    self.filter = filter
    self.sort = sort
    self.cursor = cursor
    self.limit = limit
  }

  public var __variables: Variables? { [
    "typeId": typeId,
    "tags": tags,
    "locale": locale,
    "search": search,
    "filter": filter,
    "sort": sort,
    "cursor": cursor,
    "limit": limit
  ] }

  public struct Data: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("contents", Contents.self, arguments: [
        "typeId": .variable("typeId"),
        "tags": .variable("tags"),
        "locale": .variable("locale"),
        "search": .variable("search"),
        "filter": .variable("filter"),
        "sort": .variable("sort"),
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ContentsQuery.Data.self
    ] }

    public var contents: Contents { __data["contents"] }

    /// Contents
    ///
    /// Parent Type: `ContentList`
    public struct Contents: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.ContentList }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("data", [Datum].self),
        .field("pagination", Pagination.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ContentsQuery.Data.Contents.self
      ] }

      public var data: [Datum] { __data["data"] }
      public var pagination: Pagination { __data["pagination"] }

      /// Contents.Datum
      ///
      /// Parent Type: `Content`
      public struct Datum: MetabindContent.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Content }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(ContentFields.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ContentsQuery.Data.Contents.Datum.self,
          ContentFields.self
        ] }

        public var id: MetabindContent.ID { __data["id"] }
        public var typeId: MetabindContent.ID { __data["typeId"] }
        public var packageVersion: String { __data["packageVersion"] }
        public var name: String { __data["name"] }
        public var content: String { __data["content"] }
        public var compiled: String { __data["compiled"] }
        public var tags: [String] { __data["tags"] }
        public var locale: String? { __data["locale"] }
        public var createdAt: MetabindContent.DateTime { __data["createdAt"] }
        public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }
        public var lastPublishedVersion: Int? { __data["lastPublishedVersion"] }
        public var resolvedRef: ResolvedRef { __data["resolvedRef"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var contentFields: ContentFields { _toFragment() }
        }

        public typealias ResolvedRef = ContentFields.ResolvedRef
      }

      /// Contents.Pagination
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ContentsQuery.Data.Contents.Pagination.self
        ] }

        public var cursor: String? { __data["cursor"] }
        public var hasMore: Bool { __data["hasMore"] }
        public var limit: Int { __data["limit"] }
      }
    }
  }
}
