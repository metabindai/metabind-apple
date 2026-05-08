// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct ResolvedPackageRefFields: Metabind.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment ResolvedPackageRefFields on ResolvedPackageRef { __typename package dependencies }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.ResolvedPackageRef }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("package", Metabind.ID.self),
    .field("dependencies", [Metabind.ID].self),
  ] }

  public var package: Metabind.ID { __data["package"] }
  public var dependencies: [Metabind.ID] { __data["dependencies"] }
}
