// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct ResolvedPackageDataFields: Metabind.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment ResolvedPackageDataFields on ResolvedPackageData { __typename id version components assets }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.ResolvedPackageData }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", Metabind.ID.self),
    .field("version", String.self),
    .field("components", String.self),
    .field("assets", String.self),
  ] }

  public var id: Metabind.ID { __data["id"] }
  public var version: String { __data["version"] }
  public var components: String { __data["components"] }
  public var assets: String { __data["assets"] }
}
