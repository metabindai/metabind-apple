// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class SavedSearchQuery: GraphQLQuery {
  public static let operationName: String = "SavedSearchQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query SavedSearchQuery($id: ID!) { savedSearch(id: $id) { __typename ...SavedSearchFields } }"#,
      fragments: [SavedSearchFields.self]
    ))

  public var id: ID

  public init(id: ID) {
    self.id = id
  }

  public var __variables: Variables? { ["id": id] }

  public struct Data: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("savedSearch", SavedSearch?.self, arguments: ["id": .variable("id")]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SavedSearchQuery.Data.self
    ] }

    public var savedSearch: SavedSearch? { __data["savedSearch"] }

    /// SavedSearch
    ///
    /// Parent Type: `SavedSearch`
    public struct SavedSearch: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.SavedSearch }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(SavedSearchFields.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SavedSearchQuery.Data.SavedSearch.self,
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
  }
}
