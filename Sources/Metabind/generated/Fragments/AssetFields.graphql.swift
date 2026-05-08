// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct AssetFields: Metabind.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment AssetFields on Asset { __typename id name type url size width height tags updatedAt }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Asset }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", Metabind.ID.self),
    .field("name", String.self),
    .field("type", String.self),
    .field("url", String.self),
    .field("size", Int.self),
    .field("width", Int?.self),
    .field("height", Int?.self),
    .field("tags", [String].self),
    .field("updatedAt", Metabind.DateTime.self),
  ] }

  public var id: Metabind.ID { __data["id"] }
  public var name: String { __data["name"] }
  public var type: String { __data["type"] }
  public var url: String { __data["url"] }
  public var size: Int { __data["size"] }
  public var width: Int? { __data["width"] }
  public var height: Int? { __data["height"] }
  public var tags: [String] { __data["tags"] }
  public var updatedAt: Metabind.DateTime { __data["updatedAt"] }
}
