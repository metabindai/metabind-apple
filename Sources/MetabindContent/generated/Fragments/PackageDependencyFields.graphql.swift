// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct PackageDependencyFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment PackageDependencyFields on PackageDependency { __typename projectId version }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.PackageDependency }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("projectId", MetabindContent.ID.self),
    .field("version", String.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    PackageDependencyFields.self
  ] }

  public var projectId: MetabindContent.ID { __data["projectId"] }
  public var version: String { __data["version"] }
}
