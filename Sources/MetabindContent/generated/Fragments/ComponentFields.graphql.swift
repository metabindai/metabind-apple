// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct ComponentFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment ComponentFields on Component { __typename id name compiled updatedAt }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Component }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", MetabindContent.ID.self),
    .field("name", String.self),
    .field("compiled", String.self),
    .field("updatedAt", MetabindContent.DateTime.self),
  ] }

  public var id: MetabindContent.ID { __data["id"] }
  public var name: String { __data["name"] }
  public var compiled: String { __data["compiled"] }
  public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }
}
