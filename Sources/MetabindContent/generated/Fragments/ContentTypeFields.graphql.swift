// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct ContentTypeFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment ContentTypeFields on ContentType { __typename id name packageVersion schema updatedAt }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.ContentType }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", MetabindContent.ID.self),
    .field("name", String.self),
    .field("packageVersion", String.self),
    .field("schema", String.self),
    .field("updatedAt", MetabindContent.DateTime.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    ContentTypeFields.self
  ] }

  public var id: MetabindContent.ID { __data["id"] }
  public var name: String { __data["name"] }
  public var packageVersion: String { __data["packageVersion"] }
  public var schema: String { __data["schema"] }
  public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }
}
