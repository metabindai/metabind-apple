// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class SavedSearchesQuery: GraphQLQuery {
  public static let operationName: String = "SavedSearchesQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query SavedSearchesQuery($type: SavedSearchType, $cursor: String, $limit: Int = 20) { savedSearches(type: $type, cursor: $cursor, limit: $limit) { __typename data { __typename ...SavedSearchFields } pagination { __typename cursor hasMore limit } } }"#,
      fragments: [SavedSearchFields.self]
    ))

  public var type: GraphQLNullable<GraphQLEnum<SavedSearchType>>
  public var cursor: GraphQLNullable<String>
  public var limit: GraphQLNullable<Int>

  public init(
    type: GraphQLNullable<GraphQLEnum<SavedSearchType>>,
    cursor: GraphQLNullable<String>,
    limit: GraphQLNullable<Int> = 20
  ) {
    self.type = type
    self.cursor = cursor
    self.limit = limit
  }

  public var __variables: Variables? { [
    "type": type,
    "cursor": cursor,
    "limit": limit
  ] }

  public struct Data: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("savedSearches", SavedSearches.self, arguments: [
        "type": .variable("type"),
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SavedSearchesQuery.Data.self
    ] }

    public var savedSearches: SavedSearches { __data["savedSearches"] }

    /// SavedSearches
    ///
    /// Parent Type: `SavedSearchList`
    public struct SavedSearches: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.SavedSearchList }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("data", [Datum].self),
        .field("pagination", Pagination.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SavedSearchesQuery.Data.SavedSearches.self
      ] }

      public var data: [Datum] { __data["data"] }
      public var pagination: Pagination { __data["pagination"] }

      /// SavedSearches.Datum
      ///
      /// Parent Type: `SavedSearch`
      public struct Datum: MetabindContent.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.SavedSearch }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(SavedSearchFields.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SavedSearchesQuery.Data.SavedSearches.Datum.self,
          SavedSearchFields.self
        ] }

        public var id: MetabindContent.ID { __data["id"] }
        public var name: String { __data["name"] }
        public var type: GraphQLEnum<MetabindContent.SavedSearchType> { __data["type"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var savedSearchFields: SavedSearchFields { _toFragment() }
        }
      }

      /// SavedSearches.Pagination
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
          SavedSearchesQuery.Data.SavedSearches.Pagination.self
        ] }

        public var cursor: String? { __data["cursor"] }
        public var hasMore: Bool { __data["hasMore"] }
        public var limit: Int { __data["limit"] }
      }
    }
  }
}
