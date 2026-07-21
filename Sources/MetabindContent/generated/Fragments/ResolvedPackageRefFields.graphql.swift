// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct ResolvedPackageRefFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment ResolvedPackageRefFields on ResolvedPackageRef { __typename package dependencies }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.ResolvedPackageRef }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("package", MetabindContent.ID.self),
    .field("dependencies", [MetabindContent.ID].self),
  ] }

  public var package: MetabindContent.ID { __data["package"] }
  public var dependencies: [MetabindContent.ID] { __data["dependencies"] }
}
