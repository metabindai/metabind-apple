// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct TagFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment TagFields on Tag { __typename id name slug }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Tag }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", MetabindContent.ID.self),
    .field("name", String.self),
    .field("slug", String.self),
  ] }

  public var id: MetabindContent.ID { __data["id"] }
  public var name: String { __data["name"] }
  public var slug: String { __data["slug"] }
}
