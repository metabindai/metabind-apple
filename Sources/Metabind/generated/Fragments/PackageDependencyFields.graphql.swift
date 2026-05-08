// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct PackageDependencyFields: Metabind.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment PackageDependencyFields on PackageDependency { __typename projectId version }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.PackageDependency }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("projectId", Metabind.ID.self),
    .field("version", String.self),
  ] }

  public var projectId: Metabind.ID { __data["projectId"] }
  public var version: String { __data["version"] }
}
