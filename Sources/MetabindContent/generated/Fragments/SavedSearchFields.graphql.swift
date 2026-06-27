// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct SavedSearchFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment SavedSearchFields on SavedSearch { __typename id name type }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.SavedSearch }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", MetabindContent.ID.self),
    .field("name", String.self),
    .field("type", GraphQLEnum<MetabindContent.SavedSearchType>.self),
  ] }

  public var id: MetabindContent.ID { __data["id"] }
  public var name: String { __data["name"] }
  public var type: GraphQLEnum<MetabindContent.SavedSearchType> { __data["type"] }
}
