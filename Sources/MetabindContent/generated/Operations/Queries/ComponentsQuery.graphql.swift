// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ComponentsQuery: GraphQLQuery {
  public static let operationName: String = "ComponentsQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ComponentsQuery($search: String, $cursor: String, $limit: Int = 20) { components(search: $search, cursor: $cursor, limit: $limit) { __typename data { __typename ...ComponentFields } pagination { __typename cursor hasMore limit } } }"#,
      fragments: [ComponentFields.self]
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
      .field("components", Components.self, arguments: [
        "search": .variable("search"),
        "cursor": .variable("cursor"),
        "limit": .variable("limit")
      ]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ComponentsQuery.Data.self
    ] }

    public var components: Components { __data["components"] }

    /// Components
    ///
    /// Parent Type: `ComponentList`
    public struct Components: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.ComponentList }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("data", [Datum].self),
        .field("pagination", Pagination.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ComponentsQuery.Data.Components.self
      ] }

      public var data: [Datum] { __data["data"] }
      public var pagination: Pagination { __data["pagination"] }

      /// Components.Datum
      ///
      /// Parent Type: `Component`
      public struct Datum: MetabindContent.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Component }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(ComponentFields.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ComponentsQuery.Data.Components.Datum.self,
          ComponentFields.self
        ] }

        public var id: MetabindContent.ID { __data["id"] }
        public var name: String { __data["name"] }
        public var compiled: String { __data["compiled"] }
        public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var componentFields: ComponentFields { _toFragment() }
        }
      }

      /// Components.Pagination
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
          ComponentsQuery.Data.Components.Pagination.self
        ] }

        public var cursor: String? { __data["cursor"] }
        public var hasMore: Bool { __data["hasMore"] }
        public var limit: Int { __data["limit"] }
      }
    }
  }
}
