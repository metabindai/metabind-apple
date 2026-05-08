// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct SavedSearchFields: Metabind.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment SavedSearchFields on SavedSearch { __typename id name type }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.SavedSearch }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", Metabind.ID.self),
    .field("name", String.self),
    .field("type", GraphQLEnum<Metabind.SavedSearchType>.self),
  ] }

  public var id: Metabind.ID { __data["id"] }
  public var name: String { __data["name"] }
  public var type: GraphQLEnum<Metabind.SavedSearchType> { __data["type"] }
}
