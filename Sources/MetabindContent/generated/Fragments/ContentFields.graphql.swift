// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct ContentFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment ContentFields on Content { __typename id typeId packageVersion name content compiled tags locale createdAt updatedAt lastPublishedVersion resolvedRef { __typename ...ResolvedPackageRefFields } }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Content }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", MetabindContent.ID.self),
    .field("typeId", MetabindContent.ID.self),
    .field("packageVersion", String.self),
    .field("name", String.self),
    .field("content", String.self),
    .field("compiled", String.self),
    .field("tags", [String].self),
    .field("locale", String?.self),
    .field("createdAt", MetabindContent.DateTime.self),
    .field("updatedAt", MetabindContent.DateTime.self),
    .field("lastPublishedVersion", Int?.self),
    .field("resolvedRef", ResolvedRef.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    ContentFields.self
  ] }

  public var id: MetabindContent.ID { __data["id"] }
  public var typeId: MetabindContent.ID { __data["typeId"] }
  public var packageVersion: String { __data["packageVersion"] }
  public var name: String { __data["name"] }
  public var content: String { __data["content"] }
  public var compiled: String { __data["compiled"] }
  public var tags: [String] { __data["tags"] }
  public var locale: String? { __data["locale"] }
  public var createdAt: MetabindContent.DateTime { __data["createdAt"] }
  public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }
  public var lastPublishedVersion: Int? { __data["lastPublishedVersion"] }
  public var resolvedRef: ResolvedRef { __data["resolvedRef"] }

  /// ResolvedRef
  ///
  /// Parent Type: `ResolvedPackageRef`
  public struct ResolvedRef: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.ResolvedPackageRef }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .fragment(ResolvedPackageRefFields.self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ContentFields.ResolvedRef.self,
      ResolvedPackageRefFields.self
    ] }

    public var package: MetabindContent.ID { __data["package"] }
    public var dependencies: [MetabindContent.ID] { __data["dependencies"] }

    public struct Fragments: FragmentContainer {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public var resolvedPackageRefFields: ResolvedPackageRefFields { _toFragment() }
    }
  }
}
